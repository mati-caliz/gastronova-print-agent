package main

import (
	"errors"
	"fmt"
	"go/ast"
	"go/token"
	"go/types"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	"golang.org/x/tools/go/packages"
)

const loadMode = packages.NeedName | packages.NeedFiles | packages.NeedCompiledGoFiles | packages.NeedSyntax |
	packages.NeedTypes | packages.NeedTypesInfo | packages.NeedImports

const (
	httpPackage       = "net/http"
	compositionRoot   = "main"
	constructorPrefix = "New"
)

var errLoad = errors.New("layers: no se pudieron cargar los paquetes")

// run carga los paquetes del módulo en moduleDir y devuelve los problemas contra los pendientes.
func run(moduleDir, pendingPath string, patterns []string) ([]string, error) {
	if len(patterns) == 0 {
		patterns = []string{"./..."}
	}

	moduleDir, err := filepath.Abs(moduleDir)
	if err != nil {
		return nil, fmt.Errorf("%w: %w", errLoad, err)
	}

	config := &packages.Config{
		Mode:       loadMode,
		Dir:        moduleDir,
		Tests:      false,
		Context:    nil,
		Logf:       nil,
		Env:        nil,
		BuildFlags: nil,
		Fset:       nil,
		ParseFile:  nil,
		Overlay:    nil,
	}

	loaded, err := packages.Load(config, patterns...)
	if err != nil {
		return nil, fmt.Errorf("%w: %w", errLoad, err)
	}

	loadErrors := []error{}

	packages.Visit(loaded, nil, func(pkg *packages.Package) {
		for _, loadError := range pkg.Errors {
			loadErrors = append(loadErrors, loadError)
		}
	})

	if len(loaded) == 0 || len(loadErrors) > 0 {
		return nil, errors.Join(append([]error{errLoad}, loadErrors...)...)
	}

	pending, err := readPending(filepath.Join(moduleDir, pendingPath))
	if err != nil {
		return nil, err
	}

	return compare(mixedFiles(loaded, moduleDir), pending, pendingPath), nil
}

// mixed es un archivo que atiende HTTP y consulta la base: dónde está la primera consulta.
type mixed struct {
	path     string
	position token.Position
}

// isDatabasePackage dice si el paquete es de acceso a la base: llamar a algo que recibe o devuelve sus
// tipos (un pool, una transacción, filas) es consultar la base.
func isDatabasePackage(pkg *types.Package) bool {
	if pkg == nil {
		return false
	}

	switch pkg.Path() {
	case "database/sql",
		"github.com/jackc/pgx/v5",
		"github.com/jackc/pgx/v5/pgconn",
		"github.com/jackc/pgx/v5/pgxpool":
		return true
	default:
		return false
	}
}

// mentionsDatabase dice si el tipo es, o lleva en su firma, un tipo de un paquete de base. De un tipo
// con nombre mira sólo de dónde es: lo que tenga adentro es asunto de su paquete.
func mentionsDatabase(typ types.Type, seen map[types.Type]bool) bool {
	if typ == nil || seen[typ] {
		return false
	}

	seen[typ] = true

	if named, hasName := typ.(interface{ Obj() *types.TypeName }); hasName &&
		isDatabasePackage(named.Obj().Pkg()) {
		return true
	}

	return slices.ContainsFunc(components(typ), func(component types.Type) bool {
		return mentionsDatabase(component, seen)
	})
}

// components son los tipos de los que está hecho uno sin nombre: el elemento de un puntero, una lista
// o un canal, la clave y el valor de un mapa, los parámetros y resultados de una función.
func components(typ types.Type) []types.Type {
	switch concrete := typ.(type) {
	case *types.Alias:
		return []types.Type{types.Unalias(concrete)}
	case *types.Named:
		return nil
	case *types.Map:
		return []types.Type{concrete.Key(), concrete.Elem()}
	case *types.Signature:
		return append(tupleTypes(concrete.Params()), tupleTypes(concrete.Results())...)
	case interface{ Elem() types.Type }:
		return []types.Type{concrete.Elem()}
	default:
		return nil
	}
}

func tupleTypes(tuple *types.Tuple) []types.Type {
	found := make([]types.Type, 0, tuple.Len())
	for variable := range tuple.Variables() {
		found = append(found, variable.Type())
	}

	return found
}

func calledFunction(info *types.Info, call *ast.CallExpr) *types.Func {
	switch callee := ast.Unparen(call.Fun).(type) {
	case *ast.Ident:
		function, isFunction := info.Uses[callee].(*types.Func)
		if isFunction {
			return function
		}
	case *ast.SelectorExpr:
		function, isFunction := info.Uses[callee.Sel].(*types.Func)
		if isFunction {
			return function
		}
	default:
	}

	return nil
}

// isConstructor dice si la función arma una dependencia (NewService(pool)): pasarle el pool es armado,
// no una consulta. Un constructor de un paquete de base (pgxpool.New) sigue contando.
func isConstructor(function *types.Func) bool {
	signature, isSignature := function.Type().(*types.Signature)

	return strings.HasPrefix(function.Name(), constructorPrefix) && isSignature && signature.Recv() == nil
}

// queriesDatabase dice si la llamada consulta la base: llama a un paquete de base, o a algo cuya
// firma recibe o devuelve sus tipos (un método de un pool propio, InTenant con su transacción).
func queriesDatabase(info *types.Info, call *ast.CallExpr) bool {
	function := calledFunction(info, call)
	if function != nil && isDatabasePackage(function.Pkg()) {
		return true
	}

	if function != nil && isConstructor(function) {
		return false
	}

	signature, isSignature := info.TypeOf(call.Fun).(*types.Signature)

	return isSignature && mentionsDatabase(signature, map[types.Type]bool{})
}

func importsHTTP(file *ast.File) bool {
	for _, spec := range file.Imports {
		path, err := strconv.Unquote(spec.Path.Value)
		if err == nil && path == httpPackage {
			return true
		}
	}

	return false
}

func firstQuery(info *types.Info, file *ast.File) (token.Pos, bool) {
	position, found := token.NoPos, false

	ast.Inspect(file, func(node ast.Node) bool {
		call, isCall := node.(*ast.CallExpr)
		if found || !isCall || !queriesDatabase(info, call) {
			return !found
		}

		position, found = call.Pos(), true

		return false
	})

	return position, found
}

// mixedFiles son los archivos de los paquetes que importan net/http y consultan la base. Los de
// package main quedan afuera: son el armado, que abre el pool y levanta el servidor.
func mixedFiles(loaded []*packages.Package, moduleDir string) map[string]mixed {
	found := map[string]mixed{}

	for _, pkg := range loaded {
		if pkg.Name == compositionRoot {
			continue
		}

		for index, file := range pkg.Syntax {
			if ast.IsGenerated(file) || !importsHTTP(file) {
				continue
			}

			position, queries := firstQuery(pkg.TypesInfo, file)
			if !queries {
				continue
			}

			absolute := pkg.CompiledGoFiles[index]

			relative, err := filepath.Rel(moduleDir, absolute)
			if err != nil {
				relative = absolute
			}

			relative = filepath.ToSlash(relative)
			found[relative] = mixed{path: relative, position: pkg.Fset.Position(position)}
		}
	}

	return found
}

func readPending(path string) (map[string]bool, error) {
	pending := map[string]bool{}

	content, err := os.ReadFile(filepath.Clean(path))
	if errors.Is(err, fs.ErrNotExist) {
		return pending, nil
	}

	if err != nil {
		return nil, fmt.Errorf("layers: leyendo %s: %w", path, err)
	}

	for line := range strings.Lines(string(content)) {
		entry := strings.TrimSpace(line)
		if entry != "" && !strings.HasPrefix(entry, "#") {
			pending[entry] = true
		}
	}

	return pending, nil
}

// compare devuelve los problemas, ordenados: archivos que mezclan sin estar pendientes, y pendientes
// que ya no mezclan (la lista sólo se achica).
func compare(found map[string]mixed, pending map[string]bool, pendingPath string) []string {
	problems := []string{}

	for path, file := range found {
		if !pending[path] {
			problems = append(problems, fmt.Sprintf(
				"%s:%d: atiende HTTP y consulta la base: la consulta va en otro archivo del paquete",
				path, file.position.Line,
			))
		}
	}

	for path := range pending {
		if _, stillMixed := found[path]; !stillMixed {
			problems = append(problems, fmt.Sprintf(
				"%s: ya no mezcla HTTP y base (o no existe): sacalo de %s", path, pendingPath,
			))
		}
	}

	slices.Sort(problems)

	return problems
}
