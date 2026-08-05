@echo off

echo ============================================
echo  Tiangong Medical Agent - Deploy + Start
echo  Auto-deploy on fresh machine, or just start
echo ============================================

call "%~dp0install.bat"
if errorlevel 1 exit /b 1

call "%~dp0start.bat"
exit /b %errorlevel%
