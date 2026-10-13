@echo off
set PATH=D:\ALL\setup.exe\flutter_windows_3.41.6-stable\flutter\bin;C:\Program Files\Git\cmd;C:\Program Files\Git\bin;%PATH%
cd /d frontend
flutter run -d chrome --web-port 8080
