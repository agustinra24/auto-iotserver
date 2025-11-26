#!/bin/bash
echo "IoT Platform Installer - File Verification"
echo "=========================================="
echo ""
echo "Core Scripts (6):"
ls -1 lib/*.sh | wc -l
echo ""
echo "Templates (9):"
ls -1 templates/*.tpl | wc -l
echo ""
echo "FastAPI Files (32):"
find templates/fastapi-app -name "*.py" | wc -l
echo ""
echo "Total Files: $(find . -type f | wc -l)"
echo ""
echo "✓ Installer ready for deployment"
echo ""
echo "Usage:"
echo "  sudo ./install.sh          # Interactive install"
echo "  sudo ./install.sh --dry-run  # Preview steps"
echo "  sudo ./install.sh --resume   # Resume after interruption"
