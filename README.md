# ⚡ UpdaterWinGet

A **PowerShell 5.1** script to **upgrade all installed apps via Winget** with a **terminal or GUI selector**.  
Supports multi-select, automatic Id resolution, and `WhatIf` mode for dry runs.  



## 📝 Features

- ✅ **TUI & GUI**: Choose between terminal menu or Out-GridView selection.
- 🔄 **Upgrade all apps**: Automatically detect upgradable apps from Winget.
- 🛠 **Robust ID handling**: Resolves missing/invalid IDs (handles `[no-id]` entries).
- ⚡ **Multi-select**: Supports `6,7`, `6-7`, or space-separated numbers.
- 🔍 **WhatIf mode**: Preview upgrades without executing them.
- 🖥 **Source filtering**: Limit upgrades to a specific source (e.g., `winget` or `msstore`).


## 📦 Requirements

- Windows 10/11
- PowerShell 5.1+
- [Winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/)
- (GUI mode) Out-GridView available on your system


## 🚀 Installation

1. Download the script.

2. Open PowerShell as Administrator.

3. Run the script:
```powershell
.\UpdaterWinGet.ps1 -Mode TUI
```
## 🖱 Usage

💻 Terminal (TUI)
```
.\UpdaterWinGet.ps1 -Mode TUI -WhatIf
```
Example Input:

|Input |Behavior|
|------|------------|
|6|Upgrade item #6 only|
|6,7|Upgrade items 6 and 7|
|6-7|Upgrade items 6 and 7|
|A|Upgrade all available|

## 🖼 GUI (Out-GridView)

```
.\UpdaterWinGet.ps1 -Mode UI
```
* Multi-select with Ctrl+Click

* Press OK to run upgrades

## 🔧 Parameters
|Parameter	|Type	|Description|
|-----------|-------|-----------|
|-Mode	|UI or TUI	|Choose interface mode
|-IncludeUnknown	|Switch	|Include apps with unknown versions
|-Source	|String	|Filter upgrades by source
|-WhatIf	|Switch	|Preview commands without running
|-NoElevate	|Switch	|Skip automatic elevation

## 📜 Examples
Dry run with TUI
```
.\UpdaterWinGet.ps1 -Mode TUI -WhatIf
```
Upgrade all GUI
```
.\UpdaterWinGet.ps1 -Mode UI
```
Upgrade only Winget apps
```
.\UpdaterWinGet.ps1 -Mode TUI -Source winget
```
## ⚠️ Notes

* The script attempts to resolve missing Winget IDs automatically.

* GUI mode requires Out-GridView.

* For PowerShell 7+, install [Microsoft.PowerShell.GraphicalTools](https://www.powershellgallery.com/packages/Microsoft.PowerShell.GraphicalTools/).

## ❤️ Contributing

1. Fork the repository

2. Create a feature branch

3. Submit a Pull Request

4. Star the repo ⭐

## 👤 Author
Built by Vamp (DT) for the whole world
