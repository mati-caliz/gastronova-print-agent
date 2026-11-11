package registration_test

import (
	"encoding/json"
	"path/filepath"
	"testing"

	"github.com/mati-caliz/gastronova-print-agent/internal/registration"
)

const (
	localAppData = "/usuarios/local/AppData/Local"
	packageDir   = "/WindowsApps/Gastronova.Impresion_2.3.0.0_x64"
)

func TestManifestOnlyLetsThePublishedExtensionTalkToTheHost(t *testing.T) {
	t.Parallel()

	content, err := registration.Manifest(`C:\host.exe`)
	if err != nil {
		t.Fatal(err)
	}

	var manifest struct {
		Name           string   `json:"name"`
		Path           string   `json:"path"`
		Type           string   `json:"type"`
		AllowedOrigins []string `json:"allowed_origins"`
	}

	err = json.Unmarshal(content, &manifest)
	if err != nil {
		t.Fatal(err)
	}

	if manifest.Name != registration.HostName || manifest.Path != `C:\host.exe` || manifest.Type != "stdio" {
		t.Errorf("manifiesto inesperado: %+v", manifest)
	}

	if len(manifest.AllowedOrigins) != 1 ||
		manifest.AllowedOrigins[0] != "chrome-extension://hjhbknickakeacelnjfldbbhnobdibjc/" {
		t.Errorf("orígenes permitidos inesperados: %v", manifest.AllowedOrigins)
	}
}

func TestManifestPathIsInTheUserFolder(t *testing.T) {
	t.Parallel()

	relative := filepath.Join("GastroNova", "com.gastronova.print_host.json")
	if got := registration.ManifestRelativePath(); got != relative {
		t.Errorf("ManifestRelativePath = %q, se esperaba %q", got, relative)
	}

	want := filepath.Join(localAppData, relative)
	if got := registration.ManifestPath(localAppData); got != want {
		t.Errorf("ManifestPath = %q, se esperaba %q", got, want)
	}
}

func TestHostPathPrefersTheExecutionAlias(t *testing.T) {
	t.Parallel()

	alias := filepath.Join(localAppData, "Microsoft", "WindowsApps", registration.ExecutionAlias)
	got := registration.HostPath(localAppData, packageDir, func(path string) bool { return path == alias })

	if got != alias {
		t.Errorf("HostPath = %q, se esperaba el alias %q", got, alias)
	}
}

func TestHostPathFallsBackToThePackageWhenTheAliasIsOff(t *testing.T) {
	t.Parallel()

	got := registration.HostPath(localAppData, packageDir, func(string) bool { return false })

	if want := filepath.Join(packageDir, "gastronova-print-host.exe"); got != want {
		t.Errorf("HostPath = %q, se esperaba %q", got, want)
	}
}

func TestBrowserKeysCoverChromeAndEdge(t *testing.T) {
	t.Parallel()

	want := []string{
		`Software\Google\Chrome\NativeMessagingHosts\com.gastronova.print_host`,
		`Software\Microsoft\Edge\NativeMessagingHosts\com.gastronova.print_host`,
	}

	got := registration.BrowserKeys()
	if len(got) != len(want) {
		t.Fatalf("BrowserKeys = %v", got)
	}

	for index, key := range want {
		if got[index] != key {
			t.Errorf("BrowserKeys()[%d] = %q, se esperaba %q", index, got[index], key)
		}
	}
}
