package ysyx

import chisel3._
import org.chipsalliance.cde.config.{Parameters, Config}
import freechips.rocketchip.system._
import freechips.rocketchip.diplomacy.LazyModule

object Config {
  def hasChipLink: Boolean = sys.env.getOrElse("YSYXSOC_HAS_CHIPLINK", "0") == "1"
  def sdramUseAXI: Boolean = false
  def sdramDataWidth: Int = sys.env.getOrElse("YSYXSOC_SDRAM_DATA_WIDTH", "16").toInt
  def sdramChipPairs: Int = sys.env.getOrElse("YSYXSOC_SDRAM_CHIP_PAIRS", "1").toInt
  require(sdramDataWidth == 16 || sdramDataWidth == 32,
    "SDRAM data width must be 16 or 32")
  require(sdramChipPairs == 1 || (sdramDataWidth == 32 && sdramChipPairs == 2),
    "two SDRAM chip pairs require the 32-bit interface")
}

class ysyxSoCTop extends Module {
  implicit val config: Parameters = new Config(new Edge32BitConfig ++ new DefaultRV32Config)

  val io = IO(new Bundle { })
  val dut = LazyModule(new ysyxSoCFull)
  val mdut = Module(dut.module)
  mdut.dontTouchPorts()
  mdut.externalPins := DontCare
}

object Elaborate extends App {
  val firtoolOptions = Array("--disable-annotation-unknown")
  circt.stage.ChiselStage.emitSystemVerilogFile(new ysyxSoCTop, args, firtoolOptions)
}
