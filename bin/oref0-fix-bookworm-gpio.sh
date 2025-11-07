#!/usr/bin/env bash

# Fix GPIO for Raspberry Pi OS Bookworm (kernel 6.1+)
# The cc111x library uses hardcoded BCM GPIO numbers, but Bookworm uses gpiochip512
# This means GPIO 4 (BCM) needs to be accessed as GPIO 516 (512 + 4)

echo "Checking for Raspberry Pi OS Bookworm GPIO compatibility..."

# Detect gpiochip base offset
GPIOCHIP_BASE=0
if [ -d /sys/class/gpio/gpiochip512 ]; then
    GPIOCHIP_BASE=512
    echo "Detected gpiochip512 - Bookworm/kernel 6.1+ detected"
elif [ -d /sys/class/gpio/gpiochip0 ]; then
    GPIOCHIP_BASE=0
    echo "Detected gpiochip0 - older kernel"
else
    echo "Warning: Could not detect GPIO chip base"
fi

# If we need to apply the offset
if [ "$GPIOCHIP_BASE" -gt 0 ]; then
    # Find the cc111x module
    CC111X_DIR=$(find $HOME/go/pkg/mod/github.com/ecc1 -name "cc111x@*" -type d 2>/dev/null | head -1)

    if [ -z "$CC111X_DIR" ]; then
        echo "cc111x module not found - skipping GPIO patch"
        exit 0
    fi

    echo "Found cc111x module at: $CC111X_DIR"

    # Make it writable
    chmod -R u+w "$CC111X_DIR" 2>/dev/null || true

    # Patch config_arm64.go for Raspberry Pi
    ARM64_CONFIG="$CC111X_DIR/config_arm64.go"
    if [ -f "$ARM64_CONFIG" ]; then
        # Calculate new GPIO number (base + BCM pin number)
        NEW_RESET_PIN=$((GPIOCHIP_BASE + 4))

        echo "Patching $ARM64_CONFIG: GPIO 4 -> GPIO $NEW_RESET_PIN"
        sed -i.bak "s/resetPin  = 4/resetPin  = $NEW_RESET_PIN/" "$ARM64_CONFIG"

        if grep -q "resetPin  = $NEW_RESET_PIN" "$ARM64_CONFIG"; then
            echo "Successfully patched resetPin to $NEW_RESET_PIN"
        else
            echo "Warning: Patch may have failed"
        fi
    fi

    # Patch config_arm.go for Raspberry Pi Zero/older models
    ARM_CONFIG="$CC111X_DIR/config_arm.go"
    if [ -f "$ARM_CONFIG" ]; then
        NEW_RESET_PIN=$((GPIOCHIP_BASE + 4))

        echo "Patching $ARM_CONFIG: GPIO 4 -> GPIO $NEW_RESET_PIN"
        sed -i.bak "s/resetPin  = 4/resetPin  = $NEW_RESET_PIN/" "$ARM_CONFIG"

        if grep -q "resetPin  = $NEW_RESET_PIN" "$ARM_CONFIG"; then
            echo "Successfully patched resetPin to $NEW_RESET_PIN"
        fi
    fi

    # Create rc.local to pre-export GPIO at boot
    if [ ! -f /etc/rc.local ]; then
        echo "Creating /etc/rc.local for GPIO pre-export"
        cat > /etc/rc.local << EOF
#!/bin/bash
# Pre-export GPIOs for CC111x radio with gpiochip offset
GPIOCHIP_BASE=$GPIOCHIP_BASE
RESET_GPIO=\$((GPIOCHIP_BASE + 4))

if [ ! -d /sys/class/gpio/gpio\$RESET_GPIO ]; then
    echo \$RESET_GPIO > /sys/class/gpio/export 2>/dev/null || true
    sleep 0.1
    echo out > /sys/class/gpio/gpio\$RESET_GPIO/direction 2>/dev/null || true
fi

exit 0
EOF
        chmod +x /etc/rc.local

        # Enable rc-local service
        systemctl enable rc-local 2>/dev/null || true

        # Run it now
        /etc/rc.local
    fi

    echo "GPIO fix applied - medtronic binaries will be rebuilt with correct GPIO offset"
else
    echo "No GPIO offset needed - using standard GPIO numbering"
fi

exit 0