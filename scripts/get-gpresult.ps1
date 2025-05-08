gpresult /H $env:temp\rsop.html
$html = Get-Content -Path $env:temp\rsop.html -Raw
$text = [System.Text.RegularExpressions.Regex]::Replace($html, '<[^>]+>', '')
$text | Out-File -FilePath $env:temp\rsop_extracted.txt -Encoding utf8