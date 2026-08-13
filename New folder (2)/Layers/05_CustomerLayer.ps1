# ฟังก์ชันนี้คือ Customer Layer ตัวจริงหนึ่งเดียว ไม่มีไฟล์ Customergen..txt
# แยกต่างหาก — ลูกค้าวันนี้อิสระจากประวัติร้านโดยสิ้นเชิง (ไม่อ้างอิง history/
# ยอดขายเก่า) จำลอง "คน N คนในละแวก แต่ละคนตัดสินใจแวะเองอิสระต่อกัน ด้วย
# ความน่าจะเป็น p" -> Binomial(N,p) ใช้ LFSR ของตัวเอง (ไม่ใช้ Get-Random)
# ทอยทีละคน โดย seed มาจาก system timer ความละเอียดสูงสุด ณ ขณะรัน (ข้อมูลที่
# ไม่มีใครกำหนด/ทำนายล่วงหน้าได้) — N/p คือจุดเกาะสำหรับปัจจัยภายนอกในอนาคต
# (ดู Patch Draft.txt สำหรับไอเดียที่ยังไม่ทำ)
function GenerateDailyCustomers([int]$N, [double]$p) {
  $seed = [uint16]([System.Diagnostics.Stopwatch]::GetTimestamp() -band 0xFFFF)
  $state = $seed
  if ($state -eq 0) { $state = 1 } # LFSR ห้ามเริ่มที่ 0 (ค้างที่ 0 ตลอดไม่งั้น)
  $successes = 0
  $rolls = @()
  for ($person = 1; $person -le $N; $person++) {
    for ($i = 0; $i -lt 16; $i++) {
      $bit = (($state -shr 15) -bxor ($state -shr 13) -bxor ($state -shr 12) -bxor ($state -shr 10)) -band 1
      $state = (($state -shl 1) -bor $bit) -band 0xFFFF
    }
    $roll = $state % 100
    $rolls += $roll
    if ($roll -lt ($p * 100)) { $successes++ }
  }
  $customers = [Math]::Max(1, $successes)
  return @{ customers = $customers; seed = $seed; N = $N; p = $p; successes = $successes; rolls = $rolls }
}

