# ค่าใช้จ่ายดำเนินงานที่ไม่ใช่ต้นทุนวัตถุดิบ (COGS) — ไม่นับซ้ำกับ
# totalCostWithWaste เพราะเป็นคนละหมวดรายจ่าย รวมค่าเช่าที่ย้ายมาจาก
# OutputSales() เดิมด้วย ให้ layer นี้เป็นที่เดียวของรายจ่ายคงที่/กึ่งคงที่ทั้งหมด
# ค่าเช่า 3,500 บาท/เดือน (อัตราเดิมจาก Raw Data\Stock เริ่มต้น.txt) หักซ้ำทุก
# 30 วัน (day % 30 -eq 0) — เดือนแรก 2 เดือนจ่ายล่วงหน้าไปแล้วก่อน Day 1 แล้ว
function OperatingExpenses($actualProduced, $sold, $day) {
  $waterElecBase = 50          # ค่าน้ำ(10)+ไฟพื้นฐาน(40) รวม/วัน
  $ovenElecRate  = 0.7         # บาท/ชิ้นที่ผลิต
  $packagingRate = 1.5         # บาท/ชิ้นที่ขายได้
  $rentCost = if ($day % 30 -eq 0) { 3500 } else { 0 }

  $totalProduced = ($actualProduced.Values | Measure-Object -Sum).Sum
  $totalSold     = ($sold.Values | Measure-Object -Sum).Sum
  $ovenElecCost  = $totalProduced * $ovenElecRate
  $packagingCost = $totalSold * $packagingRate
  $opExpenseCost = $waterElecBase + $ovenElecCost + $packagingCost + $rentCost

  return @{
    opExpenseCost = $opExpenseCost
    waterElecBase = $waterElecBase
    ovenElecCost  = $ovenElecCost
    packagingCost = $packagingCost
    rentCost      = $rentCost
  }
}
