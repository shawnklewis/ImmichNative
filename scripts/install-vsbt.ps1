# Installs the MSVC C++ build tools needed to compile pgvector on Windows.
# Triggers a UAC prompt.
$override = '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --silent `
    --accept-package-agreements --accept-source-agreements --override $override
"exit code: $LASTEXITCODE"
