param([int]$Port = 8792)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "SS Family: http://localhost:$Port/"
$mime = @{'.html'='text/html; charset=utf-8';'.js'='text/javascript; charset=utf-8';'.css'='text/css; charset=utf-8';'.json'='application/json; charset=utf-8'}
try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $requestPath = [uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if (-not $requestPath) { $requestPath = 'index.html' }
    $candidate = [IO.Path]::GetFullPath((Join-Path $root $requestPath))
    if (-not $candidate.StartsWith([IO.Path]::GetFullPath($root), [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      $ctx.Response.StatusCode = 404
    } else {
      $bytes = [IO.File]::ReadAllBytes($candidate)
      $type = $mime[[IO.Path]::GetExtension($candidate)]
      if (-not $type) { $type = 'application/octet-stream' }
      $ctx.Response.ContentType = $type
      $ctx.Response.ContentLength64 = $bytes.Length
      $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length)
    }
    $ctx.Response.OutputStream.Close()
  }
} finally { $listener.Stop() }
