# totalCostWithWaste ไม่ใช่เงินสดที่ต้องจ่ายใหม่ (จ่ายไปแล้วตอน reorder/
# สต็อกเริ่มต้น) จึงไม่หักออกจาก cashEnd — เก็บไว้แค่เป็นตัวเลขรายงาน COGS
# แค่สรุปเงินสดปลายวัน — รายจ่ายทั้งหมด (reorder/ค่าดำเนินงาน) คำนวณมาจาก
# layer อื่นแล้วส่งเข้ามาสำเร็จรูป
function OutputSales($cashStart, $revenue, $reorderCost, $opExpenseCost) {
  return @{ cashEnd = $cashStart + $revenue - $reorderCost - $opExpenseCost }
}
