$env:Path = 'C:\Windows\System32;C:\Windows;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Program Files\Git\cmd;D:\ALL\setup.exe\flutter_windows_3.41.6-stable\flutter\bin;' + $env:Path
Set-Location d:\ALL\Project\UbumweConnect\frontend
flutter build windows --release 2>&1 | Tee-Object -FilePath build_helper\build_log.txt
