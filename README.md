# Project site

This directory is the static source for the GitHub Pages site.

To preview it locally:

```sh
python3 -m http.server 8000 --directory Website
```

After a change, publish the directory to the Pages branch:

```sh
zsh Scripts/publish-site.sh
```

The site is served from the `gh-pages` branch at `https://hessennasser.github.io/cinema-player/`.
