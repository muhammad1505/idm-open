# Packaging scripts

## Linux
```
./scripts/package-linux.sh
```
Output: `dist/idm-open-linux.tar.gz`

## Windows (PowerShell)
```
./scripts/package-windows.ps1
```
Output: `dist/idm-open-windows.zip`

Notes:
- These scripts build release binaries with Cargo.
- For Windows, run on a Windows host with Rust installed.
