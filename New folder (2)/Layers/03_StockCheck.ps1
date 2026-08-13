function StockCheck($stockKgL, $productionOrder) {
  $stock = Normalize-Stock $stockKgL
  $needed = @{}
  foreach ($item in $productionOrder.Keys) {
    foreach ($mat in $recipe[$item].Keys) {
      if ($mat -eq "egg") { continue }
      if (-not $needed.ContainsKey($mat)) { $needed[$mat] = 0 }
      $needed[$mat] += $recipe[$item][$mat] * $productionOrder[$item]
    }
  }
  $minRatio = 1.0
  foreach ($mat in $needed.Keys) {
    $r = $stock[$mat] / $needed[$mat]
    if ($r -lt $minRatio) { $minRatio = $r }
  }

  $actualProduced = @{}
  foreach ($item in $productionOrder.Keys) {
    $actualProduced[$item] = [Math]::Floor($productionOrder[$item] * $minRatio)
  }

  $eggNeeded = 0.0
  foreach ($item in $actualProduced.Keys) { $eggNeeded += $recipe[$item].egg * $actualProduced[$item] }
  $eggActual = [Math]::Ceiling($eggNeeded)
  $eggWasteBaht = ($eggActual - $eggNeeded) * $costRates.egg

  return @{ actualProduced=$actualProduced; needed=$needed; minRatio=$minRatio; eggActual=$eggActual; eggWasteBaht=$eggWasteBaht }
}

