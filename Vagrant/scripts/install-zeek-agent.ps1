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
mkdir build
# Configure the project
cd build

# Win10 build
#cmake -DCMAKE_BUILD_TYPE:STRING=RelWithDebInfo -DZEEK_AGENT_ENABLE_INSTALL:BOOL=ON -DZEEK_AGENT_ENABLE_TESTS:BOOL=ON -DZEEK_AGENT_ZEEK_COMPATIBILITY:STRING="3.1" C:\Users\vagrant\projects\zeek-agent-master\build
#cmake -DCMAKE_VERBOSE_MAKEFILE:BOOL=true -DCMAKE_INSTALL_PREFIX:PATH='C:\Users\vagrant\projects\zeek-agent-master\install' -DCMAKE_BUILD_TYPE:STRING=RelWithDebInfo -DZEEK_AGENT_ENABLE_DOCUMENTATION:BOOL=false -DZEEK_AGENT_ENABLE_INSTALL:BOOL=true -DZEEK_AGENT_ENABLE_TESTS:BOOL=true -DZEEK_AGENT_ENABLE_SANITIZERS:BOOL=false -DZEEK_AGENT_ZEEK_COMPATIBILITY:STRING="3.1" C:\Users\vagrant\projects\zeek-agent-master\

# Jojo PC build
#cmake -DCMAKE_BUILD_TYPE:STRING=RelWithDebInfo -DZEEK_AGENT_ENABLE_INSTALL:BOOL=ON -DZEEK_AGENT_ENABLE_TESTS:BOOL=ON -DZEEK_AGENT_ZEEK_COMPATIBILITY:STRING="3.1" C:\Users\Jojo\Desktop\SecurityLab\zeek-agent\
#cmake -DCMAKE_VERBOSE_MAKEFILE:BOOL=true -DCMAKE_INSTALL_PREFIX:PATH='C:\Users\Jojo\Desktop\SecurityLab\zeek-agent\install' -DCMAKE_BUILD_TYPE:STRING=RelWithDebInfo -DZEEK_AGENT_ENABLE_DOCUMENTATION:BOOL=false -DZEEK_AGENT_ENABLE_INSTALL:BOOL=true -DZEEK_AGENT_ENABLE_TESTS:BOOL=true -DZEEK_AGENT_ENABLE_SANITIZERS:BOOL=false -DZEEK_AGENT_ZEEK_COMPATIBILITY:STRING="3.1" C:\Users\Jojo\Desktop\SecurityLab\zeek-agent\

# Build the project
cmake --build . -j2

# Run the tests
cmake --build . --target zeek_agent_tests

# Create packages
# Install Zeek Agent
cmake --build . --target install

# Configure the packaging project
mkdir package_build
cd package_build
#cmake -DZEEK_AGENT_ZEEK_COMPATIBILITY:STRING="3.1" -DZEEK_AGENT_INSTALL_PATH:PATH="C:\Users\Jojo\Desktop\SecurityLab\zeek-agent\install" -DCMAKE_INSTALL_PREFIX:PATH="C:\\Program Files\\Corelight\\Zeek Agent" C:\Users\Jojo\Desktop\SecurityLab\zeek-agent\packaging

cmake -DZEEK_AGENT_INSTALL_PATH:PATH="C:\Users\Jojo\Desktop\SecurityLab\zeek-agent\install" C:\Users\Jojo\Desktop\SecurityLab\zeek-agent\packaging

mkdir install
export DESTDIR="$(C:\Users\Jojo\Desktop\SecurityLab\zeek-agent\install)"