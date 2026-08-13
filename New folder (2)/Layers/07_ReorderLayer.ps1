# คิดราคาต้องแปลงหน่วยผ่าน unitScale ก่อนคูณ costRates เสมอ (stock/refilled
# ที่ return ยังเป็นหน่วยแสดงผล kg/L) — refilledCost เป็นส่วนเสริม breakdown
# ต้นทุนต่อวัตถุดิบเพื่อรายงาน ไม่มีผลต่อ reorderCost รวมหรือ state
# วัตถุดิบใน $panItems ซื้อได้แค่ยกแพ็ค (เช่น ไข่ 1 แผง=30 ฟอง) — เติมปัดขึ้น
# เป็นจำนวนเท่าของ $panSize[$mat] เสมอ ไม่ใช่เติมเท่าที่ขาดพอดี จึงอาจเกิน
# stockMaxRef ได้เล็กน้อย (ซื้อยกแพ็คได้แค่นั้นจริง)
function ReorderLayer($stock, $stockMaxRef, $panItems, $thresholdPct, $panSize) {
  $reorderCost = 0.0
  $refilled = @{}
  $refilledCost = @{}
  foreach ($mat in @($stock.Keys)) {
    $threshold = $thresholdPct[$mat] * $stockMaxRef[$mat]
    if ($stock[$mat] -lt $threshold) {
      $shortfall = $stockMaxRef[$mat] - $stock[$mat]
      if ($panItems -contains $mat) {
        $pack = $panSize[$mat]
        $refillAmount = [Math]::Ceiling($shortfall / $pack) * $pack
      } else {
        $refillAmount = $shortfall
      }

      $itemCost = ($refillAmount * $unitScale[$mat]) * $costRates[$mat]
      $reorderCost += $itemCost

      $stock[$mat] = $stock[$mat] + $refillAmount
      $refilled[$mat] = $refillAmount
      $refilledCost[$mat] = $itemCost
    }
  }
  return @{ stock=$stock; reorderCost=$reorderCost; refilled=$refilled; refilledCost=$refilledCost }
}

