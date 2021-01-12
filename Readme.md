# NativeDisplayBrightness

This is a fork of [https://github.com/tomun/NativeDisplayBrightness](https://github.com/tomun/NativeDisplayBrightness) by Tom Underhill.

*Control your desktop monitor brightness just like on a MacBook!*

![native brightness UI](https://raw.githubusercontent.com/vsnrain/NativeDisplayBrightness/master/image.png)

This a utility application to control monitor brightness with the <brightness-up>, <brightness-down> keys. It utilizes DDC/CI, but this app doesn't have the freezing issues that similar applications tend to suffer from.

This app also shows the **native** system UI when changing brightness! It uses the private `BezelServices` framework for this.

Needless to say, your monitor needs to support DDC/CI for this app to work.

## License

This application uses code borrowed from [ddcctl](https://github.com/kfix/ddcctl) which uses code from [DDC-CI-Tools](https://github.com/jontaylor/DDC-CI-Tools-for-OS-X)

This application also uses [DDHotKey](https://github.com/davedelong/DDHotKey) by Dave DeLong to detect increase/decrease brightness key events. 

GNU GENERAL PUBLIC LICENSE
