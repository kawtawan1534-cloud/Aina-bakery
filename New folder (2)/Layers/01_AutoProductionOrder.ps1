# floor() ตอนลดยอด (ceil() ตอนเพิ่ม) — ตั้งใจไม่สมมาตร: ใช้ ceil() ตอนลดจะปัด
# กลับไปเท่าเดิมพอดีสำหรับยอดน้อยๆ ไม่ลดจริง
#
# (แก้ 2026-08-14 — ผู้เล่นสั่งแก้บัค "Melonpan ค้างสต็อกสูงหลายวันติดทั้งที่
# ยังสั่งผลิตเพิ่ม/แช่ยอดสูงต่อ" ต้นตอคือฟังก์ชันนี้เดิมมองแค่ producedLast/
# soldLast ของ "เมื่อวานวันเดียว" ไม่เคยรู้จักสต็อกเก่าที่ค้างสะสมหลายวันใน
# staleStock1/staleStock2 เลย และ "sold >= produced" ก็ไม่แยกว่าที่ขายเกินยอด
# ผลิตเพราะมีของเก่าช่วยขาย หรือเพราะ demand ใหม่จริง — สองจุดนี้ทำให้วันที่
# ผลิตน้อยเพราะวัตถุดิบขาด (เช่น actualProduced ต่ำ) แต่ขายของเก่าที่ค้างออก
# ได้เยอะ ถูกตีความผิดเป็น "โตเต็มที่/สต็อกจำกัดจนขายหมด" ทั้งที่จริงคือของเก่า
# ยังท่วมสต็อกอยู่ — แก้ 2 จุด:
#   1) รับ $oldStockSoldLastDay (สต็อกเก่าที่ขายได้เมื่อวาน แยกจากยอดขายรวม)
#      มาคำนวณ freshSold = sold - oldStockSold ก่อนตัดสินใจ ใช้ freshSold
#      แทน sold ตรงๆ ในทุกเงื่อนไข กันสัญญาณหลอกจากของเก่าช่วยขาย
#   2) รับ $currentLeftoverStock (staleStock1+staleStock2 รวมกัน ณ ตอนตัดสินใจ
#      — คือของเก่าที่ยังค้างอยู่จริงตอนนี้) มาหักออกจากยอดที่คำนวณได้ก่อนสรุป
#      ผลลัพธ์สุดท้าย ถ้ามีของเก่าค้างเยอะ ยอดสั่งผลิตใหม่จะถูกหักลงตามจริง
#      ไม่ใช่สั่งเพิ่ม/แช่ยอดสูงซ้อนทับของเก่าที่ขายไม่ออกอยู่แล้ว
# พร้อมปิดช่องโหว่ "dead zone" เดิมที่ sellThroughRate เท่ากับ 0.5/0.75 พอดี
# ไม่เข้าเงื่อนไขไหนเลย (เปลี่ยน `<` เป็น `<=` ทั้งสองจุด)
function AutoProductionOrder($prevOrder, $producedLastDay, $soldLastDay, $oldStockSoldLastDay, $currentLeftoverStock, $items) {
  $productionOrder = @{}
  foreach ($item in $items) {
    $ordered = if ($prevOrder.ContainsKey($item)) { $prevOrder[$item] } else { 5 }
    $produced = if ($producedLastDay.ContainsKey($item)) { $producedLastDay[$item] } else { 0 }
    $sold = if ($soldLastDay.ContainsKey($item)) { $soldLastDay[$item] } else { 0 }
    $oldSold = if ($oldStockSoldLastDay.ContainsKey($item)) { $oldStockSoldLastDay[$item] } else { 0 }
    $freshSold = [Math]::Max(0, $sold - $oldSold) # ยอดขายที่มาจากของใหม่ล้วนๆ ไม่นับของเก่าช่วยขาย
    $leftover = if ($currentLeftoverStock.ContainsKey($item)) { $currentLeftoverStock[$item] } else { 0 }
    $qty = $ordered

    if ($produced -gt 0) {
      $freshSellThroughRate = $freshSold / $produced
      if ($produced -ge $ordered -and $freshSold -ge $produced) {
        $qty = [Math]::Ceiling($qty * 1.2) # เพิ่ม -> ปัดขึ้น (โตเต็มที่)
      } elseif ($produced -lt $ordered -and $freshSold -ge $produced) {
        $qty = [Math]::Ceiling(($ordered + $freshSold) / 2) # สต็อกจำกัดจนของใหม่ขายหมดเท่าที่ผลิต -> ขยับเข้าใกล้ยอดขายจริงครึ่งทาง แทนแช่ยอดเดิม
      } elseif ($freshSellThroughRate -le 0.5) {
        $qty = [Math]::Floor($qty * 0.85) # ลด -> ปัดลง (ลดจริง ไม่ปัดกลับที่เดิม)
      } elseif ($freshSellThroughRate -le 0.75) {
        $qty = [Math]::Floor($qty * 0.93)
      }
    }

    $qty = $qty - $leftover # หักของเก่าที่ยังค้างอยู่จริงออกก่อนสรุปยอดสั่งใหม่

    $productionOrder[$item] = [Math]::Max(1, $qty)
  }
  return $productionOrder
}
