$ip = (Test-Connection -ComputerName (hostname) -Count 1).IPV4Address.IPAddressToString
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Starting Flutter App with Auto-IP Injection" -ForegroundColor Green
Write-Host "Detected Laptop IP: $ip" -ForegroundColor Yellow
Write-Host "=========================================" -ForegroundColor Cyan

flutter run --dart-define=API_HOST=$ip
