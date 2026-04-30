{
  pkgs,
}:
{
  name,
  imageTar,
}:
pkgs.runCommand name {nativeBuildInputs = [pkgs.python3 pkgs.gnutar];} ''
  mkdir image rootfs
  tar -xf ${imageTar} -C image
  python - <<'PY'
  import json, os, shutil, stat, tarfile
  image_dir = "image"
  root_dir = "rootfs"
  with open(os.path.join(image_dir, "manifest.json")) as fh:
      manifest = json.load(fh)
  for layer in manifest[0]["Layers"]:
      with tarfile.open(os.path.join(image_dir, layer)) as tf:
          for member in tf.getmembers():
              base = os.path.basename(member.name)
              parent = os.path.dirname(member.name)
              if base.startswith(".wh."):
                  target = os.path.join(root_dir, parent, base[4:])
                  if os.path.isdir(target) and not os.path.islink(target):
                      shutil.rmtree(target, ignore_errors=True)
                  else:
                      try:
                          os.unlink(target)
                      except FileNotFoundError:
                          pass
                  continue
              tf.extract(member, root_dir, set_attrs=False)
              target = os.path.join(root_dir, member.name)
              if member.isfile() and not os.path.islink(target):
                  try:
                      os.chmod(target, member.mode | stat.S_IRUSR | stat.S_IWUSR)
                  except (FileNotFoundError, PermissionError):
                      pass
  PY
  mkdir -p "$out"
  cp -a rootfs/. "$out/"
''
