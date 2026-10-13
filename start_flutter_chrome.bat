@echo off
set PATH=D:\ALL\setup.exe\flutter_windows_3.41.6-stable\flutter\bin;C:\Windows\System32;C:\Windows;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Program Files\Git\cmd;%PATH%
cd /d frontend
flutter run -d chrome --web-port 9100 > flutter_chrome.log 2>&1
