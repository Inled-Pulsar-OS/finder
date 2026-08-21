# Finder (Pulsar OS Files)

![Finder Screenshot](finder_screenshot.png)

Finder is the official file explorer for **Pulsar OS**, derived from GNOME Files (Nautilus) and modified under the same **GPL-3.0** license. This derivative introduces a visual and functional experience inspired by macOS, featuring real-time folder color tagging and a dedicated color filter sidebar section.

## Key Features

* **macOS Layout**: Rounded corners, integrated controls, and a clean toolbar.
* **Color Tags**: Live folder tinting with dedicated per-color filtering in the sidebar.
* **Fluid Navigation**: Instant view updates when changing folder properties or tags.

---

## How to Build

This project uses the `meson` and `ninja` build systems.

### Prerequisites

Ensure you have the build tools and development packages for GTK4, Libadwaita, and Tracker installed on your system.

### Build Steps

1. **Configure the build directory**:
   ```bash
   meson setup _build
   ```

2. **Compile the project**:
   ```bash
   ninja -C _build
   ```

---

## How to Run & Test

You can run the compiled binary directly without installing it system-wide:

```bash
./_build/src/nautilus --new-window
```

---

## How to Install

To install the application system-wide (requires administrative privileges):

```bash
sudo ninja -C _build install
```

Or using `pkexec`:

```bash
pkexec ninja -C _build install
```
