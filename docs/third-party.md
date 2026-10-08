# Third-party files and licenses

The [MIT license](../LICENSE) covers our original tools and documentation. ASUS/AMD driver files and external build tools keep their own licenses, even when our workflow downloads or adapts them.

The APU build fetches its donor from ASUS's official download service and pinned Microsoft SDK/WDK packages from NuGet. Build tools are not included in the driver artifact; the staging helper downloads a pinned SDK tool if it needs one.

## Sources and terms

- [ASUS RC73YA driver downloads](https://www.asus.com/us/supportonly/rc73ya/helpdesk_download/)
- [AMD software license terms](https://www.amd.com/en/legal/eula/amd-software-eula.html)
- [Microsoft Windows SDK build tools](https://www.nuget.org/packages/Microsoft.Windows.SDK.BuildTools/10.0.26100.9169)
- [Microsoft Windows WDK package](https://www.nuget.org/packages/Microsoft.Windows.WDK.x64/10.0.28000.2526)
- [7-Zip license](https://www.7-zip.org/license.txt)

The generated artifact contains vendor-derived files. Publishing the adaptation tools does not relicense those files or make the package a supported Valve, ASUS, or Microsoft product.
