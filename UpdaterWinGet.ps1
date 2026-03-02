<# 
Updater WinGet
Select packages to upgrade via TUI (terminal) or GUI (Out-GridView).
Handles IDs, multi-select, and WhatIf mode.
#>

[CmdletBinding()]
param(
    [ValidateSet('UI','TUI')]
    [string]$Mode = 'UI',
    [switch]$IncludeUnknown,
    [string]$Source,
    [switch]$WhatIf,
    [switch]$NoElevate
)

# ---------- Admin ----------
function Assert-Command { param([string]$Name) try { Get-Command $Name -ErrorAction Stop | Out-Null } catch { throw "Command '$Name' not found." } }
function Ensure-Elevation { 
    param([switch]$Skip)
    if ($Skip) { return }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Elevating..."
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh.exe" } else { "powershell.exe" }
        $args = @('-ExecutionPolicy','Bypass','-File',"`"$($MyInvocation.PSCommandPath)`"")
        $psi.Arguments = $args -join ' '
        $psi.Verb = 'runas'
        [Diagnostics.Process]::Start($psi) | Out-Null
        exit
    }
}

# ---------- Helpers ----------
function FirstValue { param([object[]]$Values) foreach ($v in $Values) { if ($null -ne $v -and "$v".Trim() -ne '') { return $v } } return $null }
function TryGet { param([object]$Obj,[string[]]$Path) $cur=$Obj; foreach($seg in $Path){ if($null -eq $cur){return $null}; $p=$cur.PSObject.Properties[$seg]; if(-not $p){return $null}; $cur=$p.Value }; return $cur }
function ConvertFrom-JsonSafe { param([string]$Text) try { return $Text | ConvertFrom-Json -ErrorAction Stop } catch { return $null } }
function Extract-IdFromName { param([string]$Name) if ([string]::IsNullOrWhiteSpace($Name)) {return $null}; $m=[regex]::Match($Name,'([A-Za-z0-9]+(?:[.\-][A-Za-z0-9]+){1,})$'); if($m.Success){$c=$m.Groups[1].Value; if($c -notmatch '^\d+(\.\d+){1,4}([-\w]+)?$') { return $c }}; return $null }
function Test-Versionish { param([string]$s) if ([string]::IsNullOrWhiteSpace($s)) {return $false}; $t=$s.Trim(); if($t -match '^\d+(\.\d+){1,4}([-\w]+)?$') {return $true}; if($t -match '^[A-Za-z]{1,5}\d+[_\.-]\d') {return $true}; if($t -match '^\d{2,}[A-Za-z0-9._-]*$') {return $true}; if($t -match '_') {return $true}; return $false }
function Test-LikelyWingetId { param([string]$s) if ([string]::IsNullOrWhiteSpace($s)) {return $false}; $t=$s.Trim(); if (Test-Versionish $t){return $false}; if($t -notmatch '\.') {return $false}; if($t -match '[^\w\.-]'){return $false}; return $true }
function Resolve-PackageIdFromName { param([string]$Name,[string]$Source) $args=@('list','--name',$Name,'--output','json'); if($Source){$args+=@('--source',$Source)}; $out=winget @args 2>$null; $data=ConvertFrom-JsonSafe -Text $out; if($data){foreach($it in $data){$nm=FirstValue @(TryGet $it @('Name'),TryGet $it @('PackageName'));$id=FirstValue @(TryGet $it @('Id'),TryGet $it @('PackageIdentifier')); if($id -and $nm -and "$nm".Trim().ToLower() -eq "$Name".Trim().ToLower()){return "$id"}}; foreach($it in $data){$id=FirstValue @(TryGet $it @('Id'),TryGet $it @('PackageIdentifier')); if($id){return "$id"}}} return $null }

# ---------- Get Upgrades ----------
function Get-WinGetUpgrades {
    param([switch]$IncludeUnknown,[string]$Source)
    $args=@('upgrade','--accept-source-agreements','--output','json')
    if($IncludeUnknown){$args+='--include-unknown'} if($Source){$args+=@('--source',$Source)}
    $json=winget @args 2>$null
    $parsed=ConvertFrom-JsonSafe -Text $json
    $objs=@()
    if($parsed){
        $candidates=@()
        if($parsed -is [Array]){$candidates+=$parsed}
        if($parsed.PSObject.Properties['Packages']){$candidates+=$parsed.Packages}
        if($parsed.PSObject.Properties['Upgrades']){$candidates+=$parsed.Upgrades}
        foreach($p in $candidates){
            $name=FirstValue @(TryGet $p @('Name'),TryGet $p @('PackageName'),TryGet $p @('CatalogPackageName'))
            $id=FirstValue @(TryGet $p @('Id'),TryGet $p @('PackageIdentifier'),TryGet $p @('Package','Id'),TryGet $p @('ProductId'),TryGet $p @('PackageFamilyName'))
            $inst=FirstValue @(TryGet $p @('Installed'),TryGet $p @('InstalledVersion'),TryGet $p @('Version'))
            $avail=FirstValue @(TryGet $p @('Available'),TryGet $p @('AvailableVersion'))
            $src=FirstValue @(TryGet $p @('Source'),TryGet $p @('SourceDetails','SourceIdentifier'),TryGet $p @('CatalogSource'),TryGet $p @('Repository','Name'))
            $objs+=[pscustomobject]@{Name="$name"; Id=$id; Installed=$inst; Available=$avail; Source=$src}
        }
        return $objs | Sort-Object Name,Id,Source -Unique
    }
    # fallback text
    $text=winget upgrade 2>$null
    if(-not $text){return @()}
    $lines=$text -split "`r?`n" | Where-Object { $_.Trim() }
    $rows=$lines | Where-Object { $_ -notmatch '^(Name\s+Id\s+(Version|Installed)\s+Available(\s+Source)?|^-+)$' }
    $objs=@()
    foreach($line in $rows){
        $pattern='^(?<Name>.+?)\s{2,}(?:(?<Id>\S+)\s{2,})?(?<Installed>\S+)\s{2,}(?<Available>\S+)(?:\s{2,}(?<Source>\S+))?$'
        $m=[regex]::Match($line,$pattern)
        if($m.Success){
            $name=$m.Groups['Name'].Value.Trim()
            $idVal=$null
            if($m.Groups['Id'].Success){$tmp=$m.Groups['Id'].Value.Trim(); if($tmp -and (Test-LikelyWingetId $tmp)){$idVal=$tmp}}
            if(-not $idVal){$guess=Extract-IdFromName -Name $name;if($guess -and (Test-LikelyWingetId $guess)){$idVal=$guess;$name=($name -replace [regex]::Escape($guess)+'$','').Trim()}}
            $inst=$m.Groups['Installed'].Value.Trim();$avail=$m.Groups['Available'].Value.Trim();$src=$null
            if($m.Groups['Source'].Success){$src=$m.Groups['Source'].Value.Trim()}
            if(-not $src -and ($avail -match '^(winget|msstore)$')){$src=$avail;$avail=$null}
            $objs+=[pscustomobject]@{Name=$name; Id=$idVal; Installed=$inst; Available=$avail; Source=$src}
        }
    }
    return $objs | Sort-Object Name,Id,Source -Unique
}

# ---------- UI/TUI ----------
function Select-Packages-UI {
    param([Parameter(Mandatory)]$Packages)
    if(-not (Get-Command Out-GridView -ErrorAction SilentlyContinue)){throw "Out-GridView missing."}
    $Packages | Sort-Object Name | Out-GridView -Title "Select packages" -OutputMode Multiple
}

function Select-Packages-TUI {
    param([Parameter(Mandatory)]$Packages)
    if(-not $Packages -or $Packages.Count -eq 0){return @()}
    $indexed=@($Packages | Sort-Object Name)
    for($i=0;$i -lt $indexed.Count;$i++){ $indexed[$i]|Add-Member -NotePropertyName Index -NotePropertyValue ($i+1) -Force | Out-Null }
    Write-Host "`nAvailable updates:" -ForegroundColor Cyan
    foreach($p in $indexed){$srcTxt="";if($p.Source){$srcTxt=" ($($p.Source))"};$id=$p.Id;if(-not $id){$id='no-id'}; Write-Host ("{0,3}. {1} [{2}] {3} -> {4}{5}" -f $p.Index,$p.Name,$id,$p.Installed,$p.Available,$srcTxt)}
    Write-Host "`nSelect packages (e.g., 2,6-7, 'A' for all, Enter to cancel)"
    $choice=Read-Host "Your selection"
    if([string]::IsNullOrWhiteSpace($choice)){return @()}
    $norm=$choice.Trim() -replace '[\u2012\u2013\u2014\u2015\u2212\uFE58\uFE63\uFF0D]','-' -replace '[\uFF0C\u060C\u061B\uFE10\uFE11\u3001;；，、]',','
    
    # Initialize variable for PS5.1 TryParse
    $num = 0
    if([int]::TryParse($norm,[ref]$num)){if($num -ge 1 -and $num -le $indexed.Count){return @($indexed[$num-1])} return @()}
    if($norm.ToUpper() -eq 'A'){return $indexed}

    # Multi-select parsing
    $parts=@(); if($norm.IndexOf(',') -ge 0){$parts=$norm.Split(',')} else {$parts=$norm -split '\s+'}
    $seen=@{}; $pickedIdx=@()
    foreach($raw in $parts){$tok=$raw.Trim(); if(-not $tok){continue}
        $m=[regex]::Match($tok,'^(?<a>\d+)\s*-\s*(?<b>\d+)$'); if($m.Success){$a=[int]$m.Groups['a'].Value;$b=[int]$m.Groups['b'].Value;if($a -le $b){for($i=$a;$i -le $b;$i++){if($i -ge 1 -and $i -le $indexed.Count){if(-not $seen.ContainsKey($i)){$seen[$i]=$true;$pickedIdx+=$i}}}}; continue}
        if($tok -match '^\d+$'){$n=[int]$tok;if($n -ge 1 -and $n -le $indexed.Count){if(-not $seen.ContainsKey($n)){$seen[$n]=$true;$pickedIdx+=$n}}; continue}
        $nums=[regex]::Matches($tok,'\d+'); foreach($mm in $nums){$n=[int]$mm.Value;if($n -ge 1 -and $n -le $indexed.Count){if(-not $seen.ContainsKey($n)){$seen[$n]=$true;$pickedIdx+=$n}}}
    }
    if($pickedIdx.Count -eq 0){return @()}
    $result=@(); foreach($n in $pickedIdx){$result+=$indexed[$n-1]}; return $result
}

# ---------- Upgrade Runner ----------
function Invoke-Upgrades {
    param($Selected=@(),[switch]$WhatIf)
    $sel=@($Selected)
    if($sel.Count -eq 0){Write-Host "No packages selected."; return}
    foreach($p in $sel){
        $args=@('upgrade','--exact','--accept-package-agreements','--accept-source-agreements')
        $idToUse=$p.Id; if(-not (Test-LikelyWingetId $idToUse)){$idToUse=$null}; if(-not $idToUse){$idToUse=Extract-IdFromName -Name $p.Name;if($idToUse -and -not (Test-LikelyWingetId $idToUse)){$idToUse=$null}}
        if($idToUse){$args+=@('--id',$idToUse)}else{$args+=@('--name',$p.Name)}
        if($p.Source){$args+=@('--source',$p.Source)}
        Write-Host "`nUpgrading: $($p.Installed) -> $($p.Available) [$($idToUse -or $p.Name)]"
        if($WhatIf){Write-Host ("WHATIF: winget {0}" -f ($args -join ' ')); continue}
        & winget @args; $exit=$LASTEXITCODE
        if($exit -ne 0){$resolved=Resolve-PackageIdFromName -Name $p.Name -Source $p.Source; if($resolved){Write-Warning "Retrying with Id $resolved"; & winget upgrade --exact --accept-package-agreements --accept-source-agreements --id $resolved; $exit=$LASTEXITCODE}; if($exit -ne 0){Write-Warning "winget returned $exit for $($p.Name)"}} 
    }
}

# ---- Main with TUI loop ----
try {
    Assert-Command -Name 'winget'
    Ensure-Elevation -Skip:$NoElevate

    $upgrades = Get-WinGetUpgrades -IncludeUnknown:$IncludeUnknown -Source $Source
    if (-not $upgrades -or $upgrades.Count -eq 0) {
        Write-Host "No upgrades available." -ForegroundColor Green
        return
    }

    # Loop TUI selection until user cancels
    if ($Mode -eq 'TUI') {
        while ($true) {
            $selected = Select-Packages-TUI -Packages $upgrades
            if (-not $selected -or $selected.Count -eq 0) { 
                Write-Host "`nNo selection made. Exiting..." -ForegroundColor Yellow
                break 
            }

            Invoke-Upgrades -Selected $selected -WhatIf:$WhatIf

            # Refresh upgrades after upgrade/WhatIf
            $upgrades = Get-WinGetUpgrades -IncludeUnknown:$IncludeUnknown -Source $Source
            if (-not $upgrades -or $upgrades.Count -eq 0) {
                Write-Host "`nNo more upgrades available. Exiting..." -ForegroundColor Green
                break
            }
        }
    } else {
        # GUI mode
        $selected = Select-Packages-UI -Packages $upgrades
        if ($null -eq $selected) { $selected = @() } else { $selected = @($selected) }
        Invoke-Upgrades -Selected $selected -WhatIf:$WhatIf
    }
}
catch {
    Write-Error $_
    exit 1
}
