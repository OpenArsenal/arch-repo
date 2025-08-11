# Arch Repository

A custom Arch Linux package repository containing popular applications not available in official repos.

## 📦 Available Packages

- **1Password** - Password manager
- **1Password CLI** - Command-line interface for 1Password  
- **GitHub CLI** - Official GitHub command line tool
- **Google Chrome** - Web browser
- **Google Chrome Canary** - Developer preview browser
- **ktailctl** - Kubernetes tail control
- **Microsoft Edge** - Web browser
- **Visual Studio Code** - Code editor

## 🚀 Installation

### Add Repository

Add the following to `/etc/pacman.conf`:

```ini
[arch-repo]
SigLevel = Never
Server = https://openarsenal.github.io/arch-repo/$arch
```

### Update Package Database

```bash
sudo pacman -Sy
```

### Install Packages

```bash
# Install any package from the repo
sudo pacman -S visual-studio-code-bin google-chrome 1password

# Search available packages
pacman -Ss arch-repo
```

## 🔧 Repository Details

- **Architecture**: x86_64
- **Compression**: zstd
- **Updated**: Automatically via GitHub Actions
- **Source**: [Packages Repository](https://github.com/OpenArsenal/Packages)

## 📋 Package Information

All packages are built from PKGBUILDs in the [Packages](https://github.com/OpenArsenal/Packages) repository. Most are `-bin` packages that download and repackage official releases.

## 🛠️ Building Locally

To build packages yourself:

```bash
git clone https://github.com/OpenArsenal/arch-repo.git
cd arch-repo
./scripts/build-all.sh
```

## 📝 Contributing

Want to add a package? 

1. Create a PKGBUILD in the [Packages repository](https://github.com/OpenArsenal/Packages)
2. Submit a pull request
3. Package will be automatically built and added to this repo

## ⚠️ Disclaimer

This is a **personal repository**. Packages are provided as-is without warranty. Use at your own risk.

## 📄 License

PKGBUILDs and build scripts are MIT licensed. Individual packages retain their original licenses.