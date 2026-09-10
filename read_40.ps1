$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$workbook = $excel.Workbooks.Open('C:\Users\ormbo\OneDrive\Documents\2026\EA26\ReportTester-7955618-40.xlsx')
$sheet = $workbook.Sheets.Item(1)
$maxRow = $sheet.UsedRange.Rows.Count
$maxCol = $sheet.UsedRange.Columns.Count

Write-Host "Max Rows: $maxRow, Max Cols: $maxCol"
for ($r = 1; $r -le [math]::min(100, $maxRow); $r++) {
    $rowStr = ""
    for ($c = 1; $c -le $maxCol; $c++) {
        $cellText = $sheet.Cells.Item($r, $c).Text
        $rowStr += "$cellText | "
    }
    Write-Host $rowStr
}

$workbook.Close($false)
$excel.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
