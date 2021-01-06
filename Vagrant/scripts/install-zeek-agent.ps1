# Purpose: Installs the zeek agent

Write-Host "$('[{0:HH:mm}]' -f (Get-Date)) Installing Zeek-Agent..."

# Install CMake
Invoke-WebRequest -Uri "https://github.com/Kitware/CMake/releases/download/v${{ steps.cmake_version.outputs.VALUE }}/cmake-${{ steps.cmake_version.outputs.VALUE }}-win64-x64.msi" -OutFile "downloads\cmake-v${{ steps.cmake_version.outputs.VALUE }}.msi"
msiexec.exe /i "downloads\cmake-v${{ steps.cmake_version.outputs.VALUE }}.msi" /QN | Out-Null
echo "::set-output name=CMAKE_BINARY::C:\Program Files\CMake\bin\cmake.exe"

Invoke-WebRequest -Uri "https://github.com/Kitware/CMake/releases/download/v3.19.2/cmake-3.19.2-win64-x64.msi" -OutFile "downloads\cmake-3.19.2-win64-x64.msi"
#Invoke-WebRequest -Uri "https://github.com/Kitware/CMake/releases/download/v3.19.2/cmake-3.19.2-win64-x64.zip" -OutFile "downloads\cmake-3.
#Expand-Archive -LiteralPath C:\Archives\Invoices.Zip -DestinationPath C:\ InvoicesUnzipped
msiexec.exe /i "downloads\cmake-3.19.2-win64-x64.msi" /qn | Out-Null
$env:Path +="C:\Program Files\CMake\bin\"

# Obtain the source code
Invoke-WebRequest -Uri "https://github.com/zeek/zeek-agent/archive/master.zip" -OutFile "downloads\zeek-agent-master.zip"
Expand-Archive -LiteralPath C:\Users\vagrant\Downloads\zeek-agent-master.zip -DestinationPath C:\Users\vagrant\projects

# Create build folder
cd C:\Users\vagrant\projects\zeek-agent-master\
mkdir .\build\
# Configure the project
cd build
cmake -DCMAKE_BUILD_TYPE:STRING=RelWithDebInfo -DZEEK_AGENT_ENABLE_INSTALL:BOOL=ON -DZEEK_AGENT_ENABLE_TESTS:BOOL=ON -DZEEK_AGENT_ZEEK_COMPATIBILITY:STRING="3.1" /home/vagrant/projects/zeek-agent/
# Build the project
cmake --build . -j2

# Run the tests