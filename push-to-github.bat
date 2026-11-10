@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

set "REPO=https://github.com/etqangroup2019/masari.git"
set "BRANCH=main"

echo.
echo ========================================
echo          MASARI - GITHUB SYNC
echo ========================================
echo.

REM التحقق من تثبيت Git
where git >nul 2>&1
if errorlevel 1 (
    echo Git is not installed.
    pause
    exit /b 1
)

REM التحقق من المستودع المحلي
if not exist ".git" goto :bootstrap

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 goto :fail

REM ضبط المستودع البعيد
git remote get-url origin >nul 2>&1
if errorlevel 1 (
    git remote add origin "%REPO%"
) else (
    git remote set-url origin "%REPO%"
)
if errorlevel 1 goto :fail

REM إعداد بيانات المستخدم عند الحاجة
git config user.email >nul 2>&1
if errorlevel 1 (
    set /p "GN=Your name: "
    set /p "GE=Your email: "
    git config user.name "!GN!"
    git config user.email "!GE!"
)

REM جلب تحديثات GitHub
echo Fetching GitHub updates...
git fetch origin
if errorlevel 1 goto :fail

REM التحقق من ارتباط التاريخ المحلي بالبعيد
git merge-base HEAD origin/%BRANCH% >nul 2>&1

if errorlevel 1 (
    echo.
    echo Unrelated histories detected.
    echo Creating backup of old Git metadata...

    set "BACKUP=.git-backup-%RANDOM%-%RANDOM%"

    REM نسخ مجلد Git احتياطياً
    robocopy ".git" "!BACKUP!" /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul

    if errorlevel 8 (
        echo Backup failed. Original Git data preserved.
        goto :fail
    )

    echo Backup created: !BACKUP!

    REM حذف مجلد Git القديم بعد نجاح النسخ
    rmdir /s /q ".git"

    if exist ".git" (
        echo Cannot remove old Git metadata.
        goto :fail
    )

    goto :bootstrap
)

goto :continue


:bootstrap
echo.
echo Connecting to GitHub repository...

set "TEMP_REPO=%TEMP%\masari-bootstrap-%RANDOM%-%RANDOM%"

git clone --branch "%BRANCH%" "%REPO%" "%TEMP_REPO%"
if errorlevel 1 goto :fail

REM استعادة بيانات Git دون المساس بملفات المشروع
robocopy "%TEMP_REPO%\.git" "%CD%\.git" /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul

if errorlevel 8 (
    rmdir /s /q "%TEMP_REPO%"
    goto :fail
)

rmdir /s /q "%TEMP_REPO%"

echo Git history restored successfully.


:continue
echo.
echo Preparing changes...

git add -A
if errorlevel 1 goto :fail

REM التحقق من وجود تعديلات
git diff --cached --quiet

if errorlevel 1 (
    set "MSG="
    set /p "MSG=Commit message (Enter for default): "

    if not defined MSG set "MSG=Update Masari"

    git commit -m "!MSG!"
    if errorlevel 1 goto :fail
) else (
    echo No new changes to commit.
)

REM مزامنة التعديلات البعيدة
echo.
echo Synchronizing with GitHub...

git pull --rebase origin %BRANCH%
if errorlevel 1 (
    echo.
    echo Rebase conflict detected.
    echo Resolve conflicts before pushing.
    goto :fail
)

REM رفع المشروع
echo.
echo Pushing to GitHub...

git push -u origin %BRANCH%
if errorlevel 1 goto :fail


:ok
echo.
echo ========================================
echo       UPLOAD COMPLETED SUCCESSFULLY
echo ========================================
echo.
pause
exit /b 0


:fail
echo.
echo ========================================
echo             UPLOAD FAILED
echo ========================================
echo.
echo Local project files have not been deleted.
echo Check the error messages above.
echo.
pause
exit /b 1