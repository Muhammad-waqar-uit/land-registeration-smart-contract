@echo off
REM Windows batch script for upgrading the contract

REM Load environment variables from .env file (if exists)
if exist .env (
    for /f "usebackq tokens=1,2 delims==" %%a in (".env") do (
        set "%%a=%%b"
    )
)

REM Check required variables
if "%PRIVATE_KEY%"=="" (
    echo Error: PRIVATE_KEY not set
    exit /b 1
)

if "%PROXY_ADDRESS%"=="" (
    echo Error: PROXY_ADDRESS not set
    exit /b 1
)

if "%RPC_URL%"=="" (
    echo Error: RPC_URL not set
    exit /b 1
)

echo Upgrading Land Registry Contract...
echo Proxy Address: %PROXY_ADDRESS%
echo RPC URL: %RPC_URL%
echo.

REM Run upgrade script
forge script script/Upgrade.s.sol:Upgrade ^
    --rpc-url "%RPC_URL%" ^
    --broadcast ^
    --verify ^
    --etherscan-api-key "%ETHERSCAN_API_KEY%" ^
    -vvvv
