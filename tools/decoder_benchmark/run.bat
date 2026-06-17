@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 DATASET_DIR BENCHMARK_CMD
  exit /b 1
)
if "%~2"=="" (
  echo Usage: %~nx0 DATASET_DIR BENCHMARK_CMD
  exit /b 1
)

set "DATASET_DIR=%~1"
set "BENCHMARK_CMD=%~2"

set "FOUND=0"
for %%F in ("%DATASET_DIR%\*.json") do (
  set "FOUND=1"
  echo Running benchmark for: %%~fF
  "%BENCHMARK_CMD%" "%%~fF"
)

if "%FOUND%"=="0" (
  echo No JSON files found in %DATASET_DIR% 1>&2
  exit /b 1
)
endlocal

