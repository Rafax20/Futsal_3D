<#
.SYNOPSIS
    Script de automatizacion DevOps para Godot 4 en Windows: One-Click Deploy y Depuracion Remota en Android.

.DESCRIPTION
    Reemplaza la necesidad de usar el boton de depuracion remota de la interfaz de Godot:
    1. Verifica ADB y dispositivos Android conectados (USB o Wi-Fi) y autorizados.
    2. Ejecuta Godot 4 en modo headless para exportar la APK en depuracion (--export-debug).
    3. Instala/actualiza la APK en el dispositivo mediante adb install -r.
    4. Lanza automaticamente la actividad principal de la app en el dispositivo.
    5. Opcional (-Log): Transmite los logs del motor Godot en tiempo real mediante adb logcat.

.PARAMETER GodotBin
    Ruta al binario de Godot 4. Si se omite, se detecta automaticamente (variable GODOT_BIN, PATH o rutas estandar).

.PARAMETER AdbPath
    Ruta al ejecutable adb. Si se omite, se detecta automaticamente (variable ADB_PATH, PATH, Android SDK o configuracion de Godot).

.PARAMETER Preset
    Nombre del Preset de exportacion configurado en export_presets.cfg (Por defecto: "Android").

.PARAMETER ApkPath
    Ruta de destino del archivo APK generado (Por defecto: "./build/debug.apk").

.PARAMETER PackageName
    Nombre del paquete Android (ej. com.futsal3d.mobile). Se extrae automaticamente de export_presets.cfg si no se especifica.

.PARAMETER Activity
    Nombre de la actividad de Godot a iniciar (Por defecto: "com.godot.game.GodotApp").

.PARAMETER DeviceId
    Identificador especifico del dispositivo si hay multiples terminales conectados (ej. "192.168.10.7:5555" o serial USB).

.PARAMETER Connect
    Direccion IP[:Puerto] para conectar por Wi-Fi mediante 'adb connect' antes de verificar dispositivos.

.PARAMETER Log
    Abre inmediatamente la transmision en vivo de logs del motor (adb logcat -s godot:*) tras lanzar la app.

.PARAMETER Clean
    Fuerza la desinstalacion previa de la version existente para evitar conflictos de firmas o datos corruptos.

.PARAMETER SkipExport
    Omite la fase de exportacion de Godot y procede directo a la instalacion y lanzamiento del APK ya existente.

.EXAMPLE
    .\deploy-android.ps1
    Exporta, instala y lanza la app en el dispositivo conectado.

.EXAMPLE
    .\deploy-android.ps1 -Log
    Exporta, instala, lanza y abre la consola de logcat en vivo.

.EXAMPLE
    .\deploy-android.ps1 -SkipExport -Log
    Re-lanza la APK existente y monitoriza los logs sin re-exportar.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Ruta al binario de Godot 4")]
    [string]$GodotBin = $env:GODOT_BIN,

    [Parameter(Mandatory = $false, HelpMessage = "Ruta al ejecutable adb")]
    [string]$AdbPath = $env:ADB_PATH,

    [Parameter(Mandatory = $false, HelpMessage = "Preset de exportacion en export_presets.cfg")]
    [string]$Preset = "Android",

    [Parameter(Mandatory = $false, HelpMessage = "Ruta del APK destino")]
    [string]$ApkPath = "./build/debug.apk",

    [Parameter(Mandatory = $false, HelpMessage = "Package name de la app (ej: com.futsal3d.mobile)")]
    [string]$PackageName,

    [Parameter(Mandatory = $false, HelpMessage = "Actividad principal de inicio")]
    [string]$Activity = "com.godot.game.GodotApp",

    [Parameter(Mandatory = $false, HelpMessage = "ID del dispositivo Android objetivo")]
    [string]$DeviceId,

    [Parameter(Mandatory = $false, HelpMessage = "IP[:Puerto] para conectar por Wi-Fi si aplica")]
    [string]$Connect,

    [Parameter(Mandatory = $false, HelpMessage = "Muestra logs de Godot en tiempo real")]
    [switch]$Log,

    [Parameter(Mandatory = $false, HelpMessage = "Desinstala la app antes de reinstalar")]
    [switch]$Clean,

    [Parameter(Mandatory = $false, HelpMessage = "Omite exportacion de Godot")]
    [switch]$SkipExport
)

# Funciones de feedback visual en consola
function Write-Header([string]$text) {
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host " $text" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
}

function Write-Step([string]$step, [string]$msg) {
    Write-Host ""
    Write-Host "[$step] " -ForegroundColor Yellow -NoNewline
    Write-Host $msg -ForegroundColor White
}

function Write-Success([string]$msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-WarnMsg([string]$msg) {
    Write-Host "  [AVISO] $msg" -ForegroundColor DarkYellow
}

function Write-ErrMsg([string]$msg) {
    Write-Host "  [ERROR] $msg" -ForegroundColor Red
}

Write-Header "GODOT 4 ANDROID ONE-CLICK DEPLOY (DEVOPS PIPELINE)"

# ==============================================================================
# 0. RESOLUCION DE RUTAS Y CONFIGURACION DEL ENTORNO
# ==============================================================================

# 0.1 Buscar ADB
if (-not $AdbPath) {
    $cmdAdb = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmdAdb) {
        $AdbPath = $cmdAdb.Source
    } else {
        $adbCandidates = @(
            "C:\AndroidSDK\platform-tools\adb.exe",
            "$env:ANDROID_HOME\platform-tools\adb.exe",
            "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe",
            "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
            "C:\Program Files\Android\Android Studio\platform-tools\adb.exe"
        )
        
        $godotEditorSettings = Get-ChildItem -Path "$env:APPDATA\Godot" -Filter "editor_settings-4.*.tres" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($godotEditorSettings) {
            $sdkLines = Get-Content $godotEditorSettings.FullName -ErrorAction SilentlyContinue
            foreach ($line in $sdkLines) {
                if ($line -match 'export/android/android_sdk_path\s*=\s*"([^"]+)"') {
                    $customSdk = $matches[1].Replace("/", "\")
                    $adbCandidates = @("$customSdk\platform-tools\adb.exe") + $adbCandidates
                    break
                }
            }
        }

        foreach ($cand in $adbCandidates) {
            if ($cand -and (Test-Path $cand)) {
                $AdbPath = $cand
                break
            }
        }
    }
}

if (-not $AdbPath -or -not (Test-Path $AdbPath)) {
    Write-ErrMsg "No se encontro el ejecutable de ADB ('adb.exe')."
    Write-Host "  Define la variable de entorno ADB_PATH o agrega 'platform-tools' al PATH." -ForegroundColor DarkGray
    exit 1
}
Write-Success "ADB detectado: $AdbPath"

# 0.2 Buscar binario de Godot 4
if (-not $GodotBin) {
    $cmdGodot = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $cmdGodot) { $cmdGodot = Get-Command godot4 -ErrorAction SilentlyContinue }

    if ($cmdGodot) {
        $GodotBin = $cmdGodot.Source
    } else {
        $godotCandidates = @(
            "C:\Users\fucho\OneDrive\Escritorio\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe",
            "C:\Users\fucho\OneDrive\Escritorio\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe",
            "$env:LOCALAPPDATA\Programs\Godot\Godot_v4*_console.exe",
            "$env:ProgramFiles\Godot\godot.exe",
            "$HOME\Desktop\Godot*\godot*.exe",
            "$HOME\OneDrive\Escritorio\Godot*\godot*.exe"
        )
        foreach ($cand in $godotCandidates) {
            $resolved = Get-Item $cand -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($resolved) {
                $GodotBin = $resolved.FullName
                break
            }
        }
    }
}

if (-not $GodotBin -or -not (Test-Path $GodotBin)) {
    Write-ErrMsg "No se encontro el ejecutable de Godot 4."
    Write-Host "  Define la variable de entorno GODOT_BIN o pasa el parametro -GodotBin." -ForegroundColor DarkGray
    exit 1
}
Write-Success "Godot 4 detectado: $GodotBin"

# 0.3 Extraer PackageName de export_presets.cfg si no fue provisto
if (-not $PackageName) {
    $presetsFile = "./export_presets.cfg"
    if (Test-Path $presetsFile) {
        $presetContent = Get-Content $presetsFile -ErrorAction SilentlyContinue
        foreach ($pLine in $presetContent) {
            if ($pLine -match 'package/unique_name\s*=\s*"([^"]+)"') {
                $PackageName = $matches[1]
                break
            }
        }
    }
    if (-not $PackageName) {
        $PackageName = "com.futsal3d.mobile"
    }
}
Write-Success "Paquete objetivo: $PackageName (Actividad: $Activity)"


# ==============================================================================
# 1. VERIFICACION Y AUTORIZACION DE DISPOSITIVOS ANDROID (ADB)
# ==============================================================================
Write-Step "PASO 1/4" "Verificando conexion ADB con dispositivo Android..."

# Conexion Wi-Fi si se solicito o si esta configurada en Godot
if ($Connect) {
    Write-Host "  Intentando conectar via Wi-Fi a $Connect..." -ForegroundColor Cyan
    & $AdbPath connect $Connect | Out-Null
} else {
    $rawDevsCheck = & $AdbPath devices
    $hasAnyDev = $false
    foreach ($dLine in ($rawDevsCheck -split "`r?`n")) {
        if ($dLine -match "\b(device|unauthorized|offline)\b") {
            $hasAnyDev = $true
            break
        }
    }
    if (-not $hasAnyDev) {
        $godotEditorSettings = Get-ChildItem -Path "$env:APPDATA\Godot" -Filter "editor_settings-4.*.tres" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($godotEditorSettings) {
            $settingsContent = Get-Content $godotEditorSettings.FullName -ErrorAction SilentlyContinue
            foreach ($sLine in $settingsContent) {
                if ($sLine -match 'export/android/wifi_remote_debug_host\s*=\s*"([^"]+)"') {
                    $savedHost = $matches[1].Trim()
                    if ($savedHost -and $savedHost -ne "") {
                        Write-Host "  Auto-conectando a host Wi-Fi de Godot: $savedHost:5555..." -ForegroundColor DarkCyan
                        & $AdbPath connect "$savedHost`:5555" | Out-Null
                    }
                    break
                }
            }
        }
    }
}

# Obtener lista de dispositivos conectados
$adbOutput = & $AdbPath devices
$activeDevices = @()
$unauthorizedDevices = @()
$offlineDevices = @()

foreach ($line in ($adbOutput -split "`r?`n")) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("List of devices") -or $trimmed.StartsWith("*")) {
        continue
    }
    $parts = -split $trimmed
    if ($parts.Count -ge 2) {
        $devId = $parts[0]
        $state = $parts[1]
        switch ($state) {
            "device"       { $activeDevices += $devId }
            "unauthorized" { $unauthorizedDevices += $devId }
            "offline"      { $offlineDevices += $devId }
        }
    }
}

if ($unauthorizedDevices.Count -gt 0) {
    $unauthStr = $unauthorizedDevices -join ", "
    Write-ErrMsg "Dispositivo detectado pero NO AUTORIZADO: $unauthStr"
    Write-Host "  -> Desbloquea tu dispositivo Android y pulsa 'Permitir siempre la depuracion USB desde este equipo'." -ForegroundColor DarkYellow
    exit 1
}

if ($offlineDevices.Count -gt 0 -and $activeDevices.Count -eq 0) {
    $offStr = $offlineDevices -join ", "
    Write-ErrMsg "El dispositivo esta en estado OFFLINE: $offStr"
    Write-Host "  -> Reconecta el cable USB o reinicia el servidor ADB con: adb kill-server" -ForegroundColor DarkYellow
    exit 1
}

if ($activeDevices.Count -eq 0) {
    Write-ErrMsg "No se encontro ningun dispositivo Android conectado y autorizado."
    Write-Host ""
    Write-Host "  Recomendaciones de diagnostico:" -ForegroundColor White
    Write-Host "    1. Conecta el movil por cable USB (asegurate de que el cable admita transferencia de datos)." -ForegroundColor DarkGray
    Write-Host "    2. En el movil: Ajustes > Opciones de desarrollador > Activar 'Depuracion por USB'." -ForegroundColor DarkGray
    Write-Host "    3. Si usas Wi-Fi: ejecuta .\deploy-android.ps1 -Connect <IP_DEL_MOVIL>:5555" -ForegroundColor DarkGray
    Write-Host "    4. Ejecuta manualmente '$AdbPath devices' para comprobar el estado." -ForegroundColor DarkGray
    exit 1
}

# Seleccionar dispositivo destino
$targetDevice = ""
if ($DeviceId) {
    if ($activeDevices -contains $DeviceId) {
        $targetDevice = $DeviceId
    } else {
        $activeStr = $activeDevices -join ", "
        Write-ErrMsg "El dispositivo '$DeviceId' no esta en la lista de activos: $activeStr"
        exit 1
    }
} else {
    $targetDevice = $activeDevices[0]
}

# Obtener nombre del modelo para feedback informativo
$modelName = (& $AdbPath -s $targetDevice shell getprop ro.product.model).Trim()
$androidVer = (& $AdbPath -s $targetDevice shell getprop ro.build.version.release).Trim()
Write-Success "Dispositivo objetivo: $modelName (Android $androidVer) [ID: $targetDevice]"


# ==============================================================================
# 2. EXPORTACION HEADLESS DE GODOT 4 (--export-debug)
# ==============================================================================
$resolvedApkPath = [System.IO.Path]::GetFullPath($ApkPath)
$buildDir = Split-Path -Parent $resolvedApkPath

if (-not $SkipExport) {
    Write-Step "PASO 2/4" "Exportando APK de depuracion con Godot 4 Headless..."

    if (-not (Test-Path $buildDir)) {
        New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    }

    Write-Host "  Comando: $GodotBin --headless --export-debug `"$Preset`" `"$resolvedApkPath`"" -ForegroundColor DarkGray
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $exportProcess = Start-Process -FilePath $GodotBin `
        -ArgumentList @("--headless", "--export-debug", $Preset, $resolvedApkPath) `
        -NoNewWindow -Wait -PassThru

    $sw.Stop()

    if ($exportProcess.ExitCode -ne 0 -or -not (Test-Path $resolvedApkPath)) {
        Write-ErrMsg "Fallo la exportacion de Godot (Codigo de salida: $($exportProcess.ExitCode))."
        Write-Host "  Verifica que el preset '$Preset' exista en export_presets.cfg y que los export templates esten instalados." -ForegroundColor DarkYellow
        exit 1
    }

    $apkItem = Get-Item $resolvedApkPath
    $apkMb = [math]::Round($apkItem.Length / 1MB, 2)
    $exportSecs = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Success "Exportacion completada en ${exportSecs}s [Tamano: $apkMb MB] -> $resolvedApkPath"
} else {
    Write-Step "PASO 2/4" "Exportacion omitida por flag -SkipExport."
    if (-not (Test-Path $resolvedApkPath)) {
        Write-ErrMsg "El APK no existe en $resolvedApkPath. Ejecuta sin -SkipExport para compilarlo."
        exit 1
    }
}


# ==============================================================================
# 3. DESPLIEGUE E INSTALACION (ADB INSTALL)
# ==============================================================================
Write-Step "PASO 3/4" "Transfiriendo e instalando APK en $modelName..."

if ($Clean) {
    Write-Host "  Desinstalando version previa (-Clean)..." -ForegroundColor DarkCyan
    & $AdbPath -s $targetDevice uninstall $PackageName | Out-Null
}

$installSw = [System.Diagnostics.Stopwatch]::StartNew()
$installOutput = & $AdbPath -s $targetDevice install -r -d $resolvedApkPath 2>&1
$installSw.Stop()

$installSuccess = $false
foreach ($line in $installOutput) {
    if ($line -match "Success") {
        $installSuccess = $true
        break
    }
}

if (-not $installSuccess) {
    $outCombined = $installOutput -join " "
    Write-WarnMsg "Aviso durante la instalacion estandar: $outCombined"

    # Conflicto de firmas de APK previo
    if ($outCombined -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE" -or $outCombined -match "INSTALL_FAILED_SHARED_USER_INCOMPATIBLE") {
        Write-WarnMsg "Conflicto de firma o version detectado. Realizando desinstalacion limpia y reintentando..."
        & $AdbPath -s $targetDevice uninstall $PackageName | Out-Null
        $retryOutput = & $AdbPath -s $targetDevice install $resolvedApkPath 2>&1
        foreach ($rLine in $retryOutput) {
            if ($rLine -match "Success") {
                $installSuccess = $true
                break
            }
        }
        if (-not $installSuccess) {
            Write-ErrMsg "Fallo la reinstalacion limpia: $($retryOutput -join ' ')"
            exit 1
        }
    } else {
        Write-ErrMsg "No se pudo instalar el APK. Salida de ADB: $outCombined"
        exit 1
    }
}

$installSecs = [math]::Round($installSw.Elapsed.TotalSeconds, 1)
Write-Success "APK instalado satisfactoriamente en ${installSecs}s."


# ==============================================================================
# 4. LANZAMIENTO AUTOMATICO EN EL DISPOSITIVO
# ==============================================================================
Write-Step "PASO 4/4" "Invocando actividad principal de Godot en el dispositivo..."

# Detener cualquier instancia previa activa para un inicio limpio
& $AdbPath -s $targetDevice shell am force-stop $PackageName 2>$null

# Iniciar la actividad principal
$component = "$PackageName/$Activity"
$startOutput = & $AdbPath -s $targetDevice shell am start -n $component 2>&1
$startStr = $startOutput -join " "

# Si el identificador mDNS/Wi-Fi se renovo tras la instalacion, refrescar dispositivo
if ($startStr -match "not found" -or $startStr -match "offline") {
    Start-Sleep -Milliseconds 600
    $freshDevs = & $AdbPath devices
    $freshList = @()
    foreach ($line in ($freshDevs -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -and -not $trimmed.StartsWith("List") -and -not $trimmed.StartsWith("*")) {
            $parts = -split $trimmed
            if ($parts.Count -ge 2 -and $parts[1] -eq "device") { $freshList += $parts[0] }
        }
    }
    if ($freshList.Count -ge 1) {
        $targetDevice = $freshList[0]
        & $AdbPath -s $targetDevice shell am force-stop $PackageName 2>$null
        $startOutput = & $AdbPath -s $targetDevice shell am start -n $component 2>&1
        $startStr = $startOutput -join " "
    }
}

if ($startStr -match "Error" -or $startStr -match "does not exist") {
    Write-WarnMsg "No se pudo iniciar con $component. Probando fallback con com.godot.game.GodotApp..."
    $fallbackComp = "$PackageName/com.godot.game.GodotApp"
    $startOutput = & $AdbPath -s $targetDevice shell am start -n $fallbackComp 2>&1
    $startStr = $startOutput -join " "
    if ($startStr -match "Error") {
        Write-ErrMsg "Error al iniciar la aplicacion: $startStr"
        exit 1
    }
}

Write-Success "Juego iniciado con exito en $modelName!"
Write-Host "  Componente: $PackageName/$Activity" -ForegroundColor DarkGray


# ==============================================================================
# 5. MONITORIZACION DE LOGS (LOGCAT) SI SE ESPECIFICO -Log
# ==============================================================================
if ($Log) {
    Write-Header "TRANSMISION DE LOGCAT EN TIEMPO REAL (godot:*)"
    Write-Host " Limpiando buffer anterior y escuchando eventos del motor Godot..." -ForegroundColor DarkGray
    Write-Host " [Presiona Ctrl+C para detener la captura de logs]" -ForegroundColor DarkCyan
    Write-Host ""

    # Limpiar buffer anterior
    & $AdbPath -s $targetDevice logcat -c

    # Stream continuo filtrado a Godot
    try {
        & $AdbPath -s $targetDevice logcat -s "godot:*" "GodotApp:*" "DEBUG:*"
    } catch {
        Write-Host ""
        Write-Host "Captura de logs finalizada." -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "Para monitorizar los logs y prints de Godot en tiempo real, ejecuta:" -ForegroundColor DarkGray
    Write-Host "  .\deploy-android.ps1 -SkipExport -Log" -ForegroundColor Cyan
    Write-Host ""
}

exit 0
