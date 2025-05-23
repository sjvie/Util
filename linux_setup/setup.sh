#!/bin/bash

echo "--- Setting up ~/.bashrc ---"
curl -fsSL https://raw.githubusercontent.com/sjvie/Util/refs/heads/main/linux_setup/setup_bashrc.sh | bash

echo ""
echo "--- Setting up ~/.inputrc ---"
curl -fsSL https://raw.githubusercontent.com/sjvie/Util/refs/heads/main/linux_setup/setup_inputrc.sh | bash
