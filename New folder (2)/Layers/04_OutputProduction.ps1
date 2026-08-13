function OutputProduction($check) {
  $totalCost = 0.0
  $unitCost = @{}
  foreach ($item in $check.actualProduced.Keys) {
    $c = 0.0
    foreach ($mat in $recipe[$item].Keys) { $c += $recipe[$item][$mat] * $costRates[$mat] }
    $unitCost[$item] = $c
    $totalCost += $c * $check.actualProduced[$item]
  }
  return @{ unitCost=$unitCost; totalCostWithWaste=($totalCost + $check.eggWasteBaht) }
}

