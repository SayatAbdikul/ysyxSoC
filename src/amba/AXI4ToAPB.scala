package ysyx

import chisel3._
import chisel3.util._

import org.chipsalliance.cde.config.Parameters
import freechips.rocketchip.amba._
import freechips.rocketchip.amba.axi4._
import freechips.rocketchip.amba.apb._
import freechips.rocketchip.diplomacy._
import freechips.rocketchip.util._

case class AXI4ToAPBNode()(implicit valName: ValName) extends MixedAdapterNode(AXI4Imp, APBImp)(
  dFn = { mp =>
    APBMasterPortParameters(
      masters = mp.masters.map { m => APBMasterParameters(name = m.name, nodePath = m.nodePath) },
      requestFields = mp.requestFields.filter(!_.isInstanceOf[AMBAProtField]),
      responseKeys  = mp.responseKeys
    )
  },
  uFn = { sp =>
    val beatBytes = 4
    AXI4SlavePortParameters(
    slaves = sp.slaves.map { s =>
      val maxXfer = TransferSizes(1, beatBytes)
      require(beatBytes == 4) // only support 8-byte data AXI
      AXI4SlaveParameters(
        address       = s.address,
        resources     = s.resources,
        regionType    = s.regionType,
        executable    = s.executable,
        nodePath      = s.nodePath,
        supportsWrite = if (s.supportsWrite) TransferSizes(1, beatBytes) else TransferSizes.none,
        supportsRead  = if (s.supportsRead)  TransferSizes(1, beatBytes) else TransferSizes.none,
        interleavedId = Some(0))}, // never interleaves D beats
    beatBytes = beatBytes,
    responseFields = sp.responseFields,
    requestKeys    = sp.requestKeys.filter(_ != AMBAProt))
  }
)

class AXI4ToAPB(val aFlow: Boolean = true)(implicit p: Parameters) extends LazyModule {
  val node = AXI4ToAPBNode()

  lazy val module = new LazyModuleImp(this) {
    (node.in zip node.out) foreach { case ((in, edgeIn), (out, edgeOut)) =>
      val (ar, r, aw, w, b) = (in.ar, in.r, in.aw, in.w, in.b)

      val s_idle :: s_collect_write :: s_setup :: s_access :: s_response :: Nil = Enum(5)
      val state = RegInit(s_idle)

      val aw_pending = RegInit(false.B)
      val w_pending  = RegInit(false.B)
      val is_write   = RegInit(false.B)

      // Reads retain priority only while no write channel has been accepted.
      // Once either AW or W fires, reserve the bridge until the matching
      // channel arrives and the complete APB write finishes.
      ar.ready := state === s_idle
      val can_accept_write = ((state === s_idle) && !ar.valid) || (state === s_collect_write)
      aw.ready := can_accept_write && !aw_pending
      w.ready  := can_accept_write && !w_pending

      val have_aw = aw_pending || aw.fire
      val have_w  = w_pending  || w.fire

      switch (state) {
        is (s_idle) {
          when (ar.fire) {
            is_write := false.B
            state := s_setup
          } .elsewhen (aw.fire || w.fire) {
            is_write := true.B
            state := Mux(have_aw && have_w, s_setup, s_collect_write)
          }
        }
        is (s_collect_write) {
          when (have_aw && have_w) {
            state := s_setup
          }
        }
        is (s_setup) {
          state := s_access
        }
        is (s_access) {
          when (out.pready) {
            state := s_response
          }
        }
        is (s_response) {
          when (r.fire || b.fire) {
            aw_pending := false.B
            w_pending := false.B
            state := s_idle
          }
        }
      }

      // burst is not supported
      assert(!(ar.valid && ar.bits.len =/= 0.U))
      assert(!(aw.valid && aw.bits.len =/= 0.U))
      // size > 4 is not supported
      assert(!(ar.valid && ar.bits.size > "b10".U))
      assert(!(aw.valid && aw.bits.size > "b10".U))
      // only single-beat writes are supported
      assert(!(w.valid && !w.bits.last))

      val rid_reg    = RegEnable(ar.bits.id, ar.fire)
      val bid_reg    = RegEnable(aw.bits.id, aw.fire)
      val araddr_reg = RegEnable(ar.bits.addr, ar.fire)
      val awaddr_reg = RegEnable(aw.bits.addr, aw.fire)
      val wdata_reg  = RegEnable(w.bits.data, w.fire)
      val wstrb_reg  = RegEnable(w.bits.strb, w.fire)

      when (aw.fire) {
        aw_pending := true.B
      }
      when (w.fire) {
        w_pending := true.B
      }

      out.psel    := (state === s_setup) || (state === s_access)
      out.penable := state === s_access
      out.pwrite  := is_write
      out.paddr   := Mux(is_write, awaddr_reg, araddr_reg)
      out.pprot   := APBParameters.PROT_DEFAULT
      out.pwdata  := wdata_reg
      out.pstrb   := Mux(is_write, wstrb_reg, 0.U)

      val resp = Mux(out.pslverr, AXI4Parameters.RESP_SLVERR, AXI4Parameters.RESP_OKAY)
      val resp_reg = RegEnable(resp, (state === s_access) && out.pready)
      val rdata_reg = RegEnable(out.prdata, (state === s_access) && out.pready)

      r.valid  := !is_write && (state === s_response)
      r.bits.data := Fill(2, rdata_reg)
      r.bits.id   := rid_reg
      r.bits.resp := resp_reg
      r.bits.last := true.B

      b.valid  := is_write && (state === s_response)
      b.bits.resp := resp_reg
      b.bits.id   := bid_reg
    }
  }
}

object AXI4ToAPB {
  def apply(aFlow: Boolean = true)(implicit p: Parameters) = {
    val axi42apb = LazyModule(new AXI4ToAPB(aFlow))
    axi42apb.node
  }
}
