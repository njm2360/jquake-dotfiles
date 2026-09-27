#!/usr/bin/env bash
if mountpoint -q /mnt/rootfs.upper 2>/dev/null; then    
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  WARNING: OVERLAYROOT IS ACTIVE (tmpfs mode)     ║"
    echo "║  All changes will be lost on next reboot         ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
fi
