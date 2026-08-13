# floor() ตอนลดยอด (ceil() ตอนเพิ่ม) — ตั้งใจไม่สมมาตร: ใช้ ceil() ตอนลดจะปัด
# กลับไปเท่าเดิมพอดีสำหรับยอดน้อยๆ ไม่ลดจริง
function AutoProductionOrder($prevOrder, $producedLastDay, $soldLastDay, $items) {
  $productionOrder = @{}
  foreach ($item in $items) {
    $ordered = if ($prevOrder.ContainsKey($item)) { $prevOrder[$item] } else { 5 }
    $produced = if ($producedLastDay.ContainsKey($item)) { $producedLastDay[$item] } else { 0 }
    $sold = if ($soldLastDay.ContainsKey($item)) { $soldLastDay[$item] } else { 0 }
    $qty = $ordered

    if ($produced -gt 0) {
      $sellThroughRate = $sold / $produced
      if ($produced -ge $ordered -and $sold -ge $produced) {
        $qty = [Math]::Ceiling($qty * 1.2) # เพิ่ม -> ปัดขึ้น (โตเต็มที่)
      } elseif ($produced -lt $ordered -and $sold -ge $produced) {
        $qty = [Math]::Ceiling(($ordered + $sold) / 2) # สต็อกจำกัดจนขายหมดเท่าที่ผลิต -> ขยับเข้าใกล้ยอดขายจริงครึ่งทาง แทนแช่ยอดเดิม
      } elseif ($sellThroughRate -lt 0.5) {
        $qty = [Math]::Floor($qty * 0.85) # ลด -> ปัดลง (ลดจริง ไม่ปัดกลับที่เดิม)
      } elseif ($sellThroughRate -lt 0.75) {
        $qty = [Math]::Floor($qty * 0.93)
      }
    }

    $productionOrder[$item] = [Math]::Max(1, $qty)
  }
  return $productionOrder
}

