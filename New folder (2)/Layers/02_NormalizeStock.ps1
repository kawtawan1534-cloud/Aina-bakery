# แปลงหน่วยเก็บ/แสดงผล (kg/L/ฟอง) -> หน่วยคำนวณสูตร (g/mL/ฟอง) ตามตัวคูณที่ประกาศ
# ไว้ใน unitScale — ไม่ฮาร์ดโค้ดรายชื่อวัตถุดิบ วัตถุดิบใหม่จึงไม่หลุดการแปลงหน่วย
function Normalize-Stock($s) {
  $out = @{}
  foreach ($mat in $s.Keys) { $out[$mat] = $s[$mat] * $unitScale[$mat] }
  return $out
}

