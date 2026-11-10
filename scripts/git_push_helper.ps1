# ==============================================================================
# Git Initialization & Push Helper for Brain Condition Detector SoC
# ==============================================================================
Param(
    [string]$RemoteUrl = ""
)

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "   Git Repository Setup - Brain Condition Detector (BCD) SoC     " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan

# Check if git is available
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Write-Warning "Git executable was not found in your system PATH."
    Write-Host "Please install Git for Windows from: https://git-scm.com/download/win"
    Write-Host "Or open this directory in GitHub Desktop or Visual Studio Code to push."
    return
}

# 1. Initialize git repo if not already initialized
if (-not (Test-Path ".git")) {
    Write-Host "[1/5] Initializing Git repository..." -ForegroundColor Yellow
    git init
} else {
    Write-Host "[1/5] Git repository already initialized." -ForegroundColor Green
}

# 2. Stage files
Write-Host "[2/5] Staging files (respecting .gitignore)..." -ForegroundColor Yellow
git add .

# 3. Create initial commit
Write-Host "[3/5] Committing changes..." -ForegroundColor Yellow
git commit -m "feat: complete Brain Condition Detector SoC with VeeR EL2 core, Dual AI NPU/Swin accelerators, and UVM 1.2 testbench"

# 4. Set default branch to main
git branch -M main

# 5. Remote and push
if ($RemoteUrl -ne "") {
    Write-Host "[4/5] Adding remote repository: $RemoteUrl..." -ForegroundColor Yellow
    git remote remove origin -ErrorAction SilentlyContinue
    git remote add origin $RemoteUrl
    Write-Host "[5/5] Pushing to remote repository..." -ForegroundColor Green
    git push -u origin main
} else {
    Write-Host "`nRepository is committed locally on branch 'main'!" -ForegroundColor Green
    Write-Host "To link to your remote GitHub repository, run:"
    Write-Host "  git remote add origin <YOUR_GITHUB_REPO_URL>" -ForegroundColor Yellow
    Write-Host "  git push -u origin main" -ForegroundColor Yellow
}
