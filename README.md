# nvm-ps
nvm for Windows in PowerShell

### Quickstart
Run the following into a cmd prompt:
```
powershell -c "& { iwr https://raw.githubusercontent.com/grumpycoders/nvm-ps/master/nvm.ps1 | iex }"
```

### What ?
This is a version of the [Node Version Manager](https://github.com/creationix/nvm/blob/master/README.md) written for Microsoft Windows using PowerShell.

### Why ?
I needed something fairly idiomatic that was going to work on my corporate-controlled machine, without any weird dependency, such as Visual Basic Script which is disabled there for me.

### How ?
Just like the normal nvm, you should be able to run commands such as `nvm install 8`, `nvm ls`, `nvm ls-remote`, and `nvm use v8.9.1`. This software is extremely new, and surely contains bugs and is missing a lot of features from what the bash version of nvm can do.

### Who ?
My name is Nicolas Noble, I write code for a living, and I need software that Just Works For Me. This is my very first exposure to PowerShell, so please be gentle.
