# IncubatorEDU schools banner

Editable vertical IncubatorEDU schools banner. The current version is 1080×1920 (9:16), with landscape variations retained for other placements.

## Edit

Open `banner-1080x1920.html` in a browser. It intentionally contains only the IncubatorEDU mark and the five school logos. Adjust their positioning and size in the CSS if needed.

Useful CSS values are grouped at the beginning of the file under `:root`. Logo files live in `assets/` and can be replaced without changing the layout when filenames stay the same.

## Export with Chrome

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new \
  --hide-scrollbars \
  --disable-gpu \
  --window-size=1080,1920 \
  --screenshot=incubator-schools-1080x1920.png \
  "file://$(pwd)/banner-1080x1920.html"
```

## Source assets

- IncubatorEDU wordmark: `https://www.unchartedlearning.org/hubfs/Website_Templates/Incubator_2018/logo-incubator.svg`
- Centennial mark: `https://rr-production-2022.s3.us-west-000.backblazeb2.com/uploadteam_logo/Centennial%20HS_82664.png`
- Emerson, Frisco, Heritage, and Lone Star marks: matching transparent assets from `https://www.txhslogoproject.com/`

The marks remain the property of their respective organizations. This layout assumes the user has permission to use the supplied school and program branding.
