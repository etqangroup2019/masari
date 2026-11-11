@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
set "REPO=https://github.com/etqangroup2019/masari.git"
set "BRANCH=main"
set "FIRST=0"

echo.
echo ========================================
echo  MASARI - GITHUB SYNC
echo ========================================
echo.

rem ---- Git must be installed
where git >nul 2>&1
if errorlevel 1 (
  echo Git is not installed. Download it from https://git-scm.com/download/win
  goto :fail
)

rem ---- keep this script out of the repository
if not exist ".gitignore" echo push-to-github.bat> .gitignore

rem ---- make sure a local repository exists
if not exist ".git" (
  echo Creating a local repository...
  git init >nul
  if errorlevel 1 goto :fail
)
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
  echo The .git folder is damaged. It will be backed up and rebuilt from GitHub.
  goto :adopt
)

rem ---- a repository with no commits yet: name its branch
git rev-parse --verify HEAD >nul 2>&1
if errorlevel 1 git branch -M %BRANCH% >nul 2>&1

rem ---- remote
git remote get-url origin >nul 2>&1
if errorlevel 1 (
  git remote add origin "%REPO%"
) else (
  git remote set-url origin "%REPO%"
)
if errorlevel 1 goto :fail

echo Fetching GitHub updates...
git fetch origin
if errorlevel 1 (
  echo Could not reach GitHub. Check the internet connection and the login.
  goto :fail
)

rem ---- empty remote: this is the first upload
git ls-remote --exit-code --heads origin %BRANCH% >nul 2>&1
if errorlevel 1 (
  echo The branch "%BRANCH%" does not exist on GitHub yet. This will be the first upload.
  goto :commit
)

rem ---- is the local history connected to the GitHub history?
git merge-base HEAD origin/%BRANCH% >nul 2>&1
if not errorlevel 1 goto :commit
echo.
echo The local Git history is not connected to the GitHub history.
echo Your project files are kept. Only the Git metadata is replaced.

:adopt
set "FIRST=1"
set "BACKUP=%USERPROFILE%\masari-git-backups\git-%RANDOM%-%RANDOM%"
if exist ".git" (
  echo Backing up the old Git metadata to: !BACKUP!
  mkdir "!BACKUP!" >nul 2>&1
  robocopy ".git" "!BACKUP!" /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul
  if errorlevel 8 (
    echo Backup failed. Nothing was changed.
    goto :fail
  )
  rmdir /s /q ".git"
  if exist ".git" (
    echo Could not remove the old .git folder. Close programs that use it and try again.
    goto :fail
  )
)

echo.
echo Connecting to the GitHub repository...
set "TMPREPO=%TEMP%\masari-bootstrap-%RANDOM%-%RANDOM%"
git clone --no-checkout --branch "%BRANCH%" "%REPO%" "!TMPREPO!"
if errorlevel 1 goto :fail
robocopy "!TMPREPO!\.git" "%CD%\.git" /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP >nul
set "RC=!ERRORLEVEL!"
rmdir /s /q "!TMPREPO!" >nul 2>&1
if !RC! GEQ 8 (
  echo Could not restore the Git history.
  goto :fail
)
git reset -q
if errorlevel 1 goto :fail
echo Git history restored. Your local files were not touched.

:commit
echo.
echo Preparing changes...
if "%FIRST%"=="1" (
  git add --ignore-removal .
  if errorlevel 1 goto :fail
  rem files that exist only on GitHub are restored into this folder, never deleted from GitHub
  git checkout -- .
) else (
  git add -A
)
if errorlevel 1 goto :fail

rem ---- commit identity
git config user.email >nul 2>&1
if errorlevel 1 (
  echo First time setup: Git needs your name and email for commits.
  set /p "GN=Your name: "
  set /p "GE=Your email: "
  git config user.name "!GN!"
  git config user.email "!GE!"
)

git diff --cached --quiet
if errorlevel 1 (
  set "MSG="
  set /p "MSG=Commit message (Enter for default): "
  if not defined MSG set "MSG=Update Masari"
  set "MSG=!MSG:"=!"
  git commit -m "!MSG!"
  if errorlevel 1 goto :fail
) else (
  echo No new changes to commit.
)

rem ---- bring in remote changes, then push
echo.
echo Synchronizing with GitHub...
git ls-remote --exit-code --heads origin %BRANCH% >nul 2>&1
if not errorlevel 1 (
  git pull --rebase origin %BRANCH%
  if errorlevel 1 (
    echo.
    echo Rebase conflict detected. The rebase was cancelled so nothing is lost.
    git rebase --abort >nul 2>&1
    echo Resolve the conflict in the files, then run this file again.
    goto :fail
  )
)

echo.
echo Pushing to GitHub...
git push -u origin HEAD:%BRANCH%
if errorlevel 1 goto :fail

echo.
echo ========================================
echo  UPLOAD COMPLETED SUCCESSFULLY
echo ========================================
echo.
pause
exit /b 0

:fail
echo.
echo ========================================
echo  UPLOAD FAILED
echo ========================================
echo.
echo Your local project files have not been deleted.
echo Read the messages above to see what went wrong.
echo.
pause
exit /b 1
