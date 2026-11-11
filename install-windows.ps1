& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    $releaseVersion = '__VERSION__'
    $expectedInstallerHash = '__INSTALLER_SHA256__'
    $installerUrl = "https://github.com/mati-caliz/gastronova-print-agent/releases/download/v$releaseVersion/gastronova-impresion.exe"
    $nativeHostRegistryKey = 'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.gastronova.print_host'
    $supportEmail = 'soporte@gastronova.com.ar'
    $launchedFromRunDialog = [Environment]::GetCommandLineArgs() -match '^-c(ommand)?$'

    function Write-ConsoleLine([string] $text, [ConsoleColor] $color = $Host.UI.RawUI.ForegroundColor) {
        $Host.UI.WriteLine($color, $Host.UI.RawUI.BackgroundColor, "  $text")
    }

    function Write-Step([string] $message) {
        Write-ConsoleLine "> $message" Gray
    }

    function Wait-BeforeClosing {
        if ($launchedFromRunDialog) {
            Write-ConsoleLine ''
            [void](Read-Host '  Apretá Enter para cerrar esta ventana')
        }
    }

    Write-ConsoleLine ''
    Write-ConsoleLine 'Gastronova · Componente de impresión' Cyan
    Write-ConsoleLine ''

    if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
        Write-ConsoleLine 'Este instalador es para Windows. En Mac y Linux bajá el instalador desde Gastronova.' Yellow
        Wait-BeforeClosing
        return
    }

    $installerPath = Join-Path $env:TEMP "gastronova-impresion-$releaseVersion.exe"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        Write-Step 'Descargando el componente...'
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

        $downloadedHash = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash
        if ($downloadedHash -ne $expectedInstallerHash) {
            throw 'La descarga llegó incompleta o dañada. Volvé a intentarlo en un rato.'
        }

        Write-Step 'Instalando...'
        $installation = Start-Process -FilePath $installerPath -ArgumentList '/S' -Wait -PassThru
        if ($installation.ExitCode -ne 0) {
            throw "El instalador terminó con el código $($installation.ExitCode)."
        }
        if (-not (Test-Path $nativeHostRegistryKey)) {
            throw 'El instalador terminó, pero Chrome todavía no ve el componente.'
        }

        Write-ConsoleLine ''
        Write-ConsoleLine 'Listo: el componente de impresión quedó instalado.' Green
        Write-ConsoleLine 'Cerrá Chrome del todo y volvé a abrirlo: Gastronova lo va a mostrar como «Conectado».'
    }
    catch {
        Write-ConsoleLine ''
        Write-ConsoleLine "No se pudo instalar: $($_.Exception.Message)" Red
        Write-ConsoleLine "Si vuelve a pasar, escribinos a $supportEmail y te ayudamos."
    }
    finally {
        Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
    }

    Wait-BeforeClosing
}
