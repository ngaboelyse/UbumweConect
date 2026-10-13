@echo off
set PATH=D:\ALL\setup.exe\flutter_windows_3.41.6-stable\flutter\bin;C:\Windows\System32;%PATH%
cd /d d:\ALL\Project\UbumweConnect\frontend
flutter run -d chrome --web-port 8080 > d:\ALL\Project\UbumweConnect\flutter_chrome.log 2>&1
