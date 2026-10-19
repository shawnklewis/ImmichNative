@echo off
rem Builds pgvector for the portable PostgreSQL in tools\pgsql and installs it there.
setlocal
set "ROOT=%~dp0.."
set "PGROOT=%ROOT%\tools\pgsql"
set "SRC=%ROOT%\vendor\pgvector"

call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1

if not exist "%SRC%" git clone --branch v0.8.1 --depth 1 https://github.com/pgvector/pgvector.git "%SRC%" || exit /b 1
cd /d "%SRC%"
nmake /F Makefile.win clean
nmake /F Makefile.win || exit /b 1
nmake /F Makefile.win install || exit /b 1
echo pgvector built and installed into %PGROOT%
