$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$workbook = $excel.Workbooks.Open('C:\Users\ormbo\OneDrive\Documents\2026\EA26\ReportTester-7955618-3.xlsx')
$csvPath = 'C:\Users\ormbo\OneDrive\Documents\2026\EA26\Report3.csv'
$workbook.SaveAs($csvPath, 6) # 6 = xlCSV
$workbook.Close($false)
$excel.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
