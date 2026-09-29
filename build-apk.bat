@echo off
echo ========================================
echo  QistBook APK Builder
echo ========================================
echo.
echo Step 1: Dependencies download ho rahi hain...
call flutter pub get
if %errorlevel% neq 0 (
    echo ERROR: flutter pub get fail hua. Flutter install hai?
    pause
    exit /b 1
)
echo.
echo Step 2: APK ban rahi hai (5-10 minute lag sakte hain)...
call flutter build apk --release
if %errorlevel% neq 0 (
    echo ERROR: Build fail hui.
    pause
    exit /b 1
)
echo.
echo ========================================
echo  APK TAYYAR HAI!
echo  Location: build\app\outputs\flutter-apk\app-release.apk
echo ========================================
pause
