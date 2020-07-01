<html>
<head>
<title>Reboot</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
</head/>
<body>
<form method="post">
  <button type="submit">Reboot</button>
  <input type="hidden" name="mode" value="reboot">
</form>
<form method="post">
  <button type="submit">Shutdown</button>
  <input type="hidden" name="mode" value="shutdown">
</form>
<?php
if ($_POST["mode"] == "reboot") {
  echo "Rebooting...";
  exec('sudo /sbin/reboot');
}
if ($_POST["mode"] == "shutdown") {
  echo "Shutting down...";
  exec('sudo /sbin/shutdown -h now');
}
?>
</body>
</html>
