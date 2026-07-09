# Tip QR code

Put your tip QR image in this directory with a fixed filename:

- `wechat-tip.png` — WeChat tip QR code

Recommended specs:

- Square PNG, edge ≥ 600px (README displays at 220px; extra resolution helps on Retina);
- Prefer a plain white or light background;
- Prefer non-indexed (RGB/RGBA) PNG so Markdown previews render reliably;
- If you add slogan text on the image, keep at least ~40px quiet margin at the corners so scanning still works.

After replacing the file, no README path changes are needed — both [`README.md`](../../README.md) and [`README.zh-CN.md`](../../README.zh-CN.md) load `docs/images/donate/wechat-tip.png`.

## Privacy

If you fork this project and keep a tip section, **only commit your own QR code** — never upload someone else’s payment QR to a public repo. Tips go to whoever uploaded the code, not necessarily the upstream author.
