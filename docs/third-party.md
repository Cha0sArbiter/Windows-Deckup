# Third-party materials

The MIT license applies to original tools and documentation, not donor drivers, catalogs, configurations or Microsoft/7-Zip tools. The APU build downloads the ASUS donor from its official CDN and Microsoft SDK/WDK NuGet packages from NuGet. Downloaded tools are not included in the driver artifact; a staging helper fetches the pinned SDK tool when needed.

Sources and terms:
- [ASUS RC73YA support](https://www.asus.com/us/supportonly/rc73ya/helpdesk_download/)
- [AMD software terms](https://www.amd.com/en/legal/eula/amd-software-eula.html)
- [Windows SDK build tools](https://www.nuget.org/packages/Microsoft.Windows.SDK.BuildTools/10.0.26100.9169)
- [Windows WDK package](https://www.nuget.org/packages/Microsoft.Windows.WDK.x64/10.0.28000.2526)
- [7-Zip licensing](https://www.7-zip.org/license.txt)

Generated driver artifacts are vendor-derived experimental packages. Publishing project tools does not relicense vendor files or establish a supported Windows/Steam Deck product.
