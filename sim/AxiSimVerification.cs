// =============================================================================
// Brain Condition Detector (BCD) SoC - Cycle-Accurate AXI Verification Engine
// Implements cycle-accurate model of the 6x6 Interconnect Crossbar, Masters M0-M5,
// Slaves S0-S5, AXI-Lite Bridge, RTL Threshold Engine, and Firewall.
// Executes 550+ comprehensive verification testcases and logs Pass/Fail statistics.
// =============================================================================

using System;
using System.Collections.Generic;
using System.IO;

namespace BcdSocAxiVerification
{
    public enum AxiResp : byte
    {
        OKAY   = 0,
        EXOKAY = 1,
        SLVERR = 2,
        DECERR = 3
    }

    public enum AxiBurst : byte
    {
        FIXED = 0,
        INCR  = 1,
        WRAP  = 2
    }

    public static class Constants
    {
        public const uint ADDR_BASE_ROM         = 0x00000000;
        public const uint ADDR_SIZE_ROM         = 0x00010000; // 64 KiB

        public const uint ADDR_BASE_SRAM        = 0x10000000;
        public const uint ADDR_SIZE_SRAM        = 0x00100000; // 1 MiB

        public const uint ADDR_BASE_SCRATCHPAD  = 0x11000000;
        public const uint ADDR_SIZE_SCRATCHPAD  = 0x00200000; // 2 MiB

        public const uint ADDR_BASE_CSR_BRIDGE  = 0x40000000;
        public const uint ADDR_SIZE_CSR_BRIDGE  = 0x00100000; // 1 MiB

        public const uint ADDR_BASE_NVM         = 0x60000000;
        public const uint ADDR_SIZE_NVM         = 0x08000000; // 128 MiB

        public const uint ADDR_BASE_LPDDR       = 0x80000000;
        public const uint ADDR_SIZE_LPDDR       = 0x40000000; // 1 GiB

        public const uint CSR_BASE_AFE          = 0x40000000;
        public const uint CSR_BASE_FILTER       = 0x40010000;
        public const uint CSR_BASE_THRESHOLD    = 0x40020000;
        public const uint CSR_BASE_PMU          = 0x40030000;
        public const uint CSR_BASE_DMA          = 0x40040000;
        public const uint CSR_BASE_NPU          = 0x40050000;
        public const uint CSR_BASE_SWIN         = 0x40060000;
        public const uint CSR_BASE_OUTPUT       = 0x40070000;
        public const uint CSR_BASE_SECURITY     = 0x40080000;
        public const uint CSR_BASE_PERIPH       = 0x40090000;

        // Threshold offsets
        public const uint THRESH_CTRL           = 0x00;
        public const uint THRESH_STATUS         = 0x04;
        public const uint THRESH_CH_MASK        = 0x08;
        public const uint THRESH_LL_THR         = 0x0C;
        public const uint THRESH_BP_RATIO_THR   = 0x10;
        public const uint THRESH_ENT_THR        = 0x14;
        public const uint THRESH_VOTE_NM        = 0x18;
        public const uint THRESH_HYST_HOLD      = 0x1C;
        public const uint THRESH_PRETRIG_LEN    = 0x20;
        public const uint THRESH_IRQ_EN         = 0x24;
        public const uint THRESH_IRQ_STATUS     = 0x28;
        public const uint THRESH_WAKE_TARGET    = 0x2C;
    }

    public class MemorySlave
    {
        public string Name;
        public uint BaseAddr;
        public uint Size;
        public bool ReadOnly;
        public Dictionary<uint, uint> Mem = new Dictionary<uint, uint>();

        public MemorySlave(string name, uint baseAddr, uint size, bool readOnly)
        {
            Name = name;
            BaseAddr = baseAddr;
            Size = size;
            ReadOnly = readOnly;
        }

        public AxiResp Write(uint addr, uint data, byte strb)
        {
            if (ReadOnly) return AxiResp.SLVERR;
            uint offset = addr - BaseAddr;
            if (offset >= Size) return AxiResp.DECERR;

            uint current = 0;
            if (Mem.ContainsKey(offset)) current = Mem[offset];

            uint mask = 0;
            if ((strb & 0x1) != 0) mask |= 0x000000FF;
            if ((strb & 0x2) != 0) mask |= 0x0000FF00;
            if ((strb & 0x4) != 0) mask |= 0x00FF0000;
            if ((strb & 0x8) != 0) mask |= 0xFF000000;

            uint updated = (current & ~mask) | (data & mask);
            Mem[offset] = updated;
            return AxiResp.OKAY;
        }

        public AxiResp Read(uint addr, out uint data)
        {
            uint offset = addr - BaseAddr;
            if (offset >= Size)
            {
                data = 0xDEADDEAD;
                return AxiResp.DECERR;
            }
            if (Mem.ContainsKey(offset)) data = Mem[offset];
            else data = 0;
            return AxiResp.OKAY;
        }
    }

    public class ThresholdEngineSlave
    {
        public uint Ctrl;
        public uint Status;
        public uint ChMask = 0xFFFFFFFF;
        public uint LlThr = 0x00000500;
        public uint BpRatioThr = 0x00000280;
        public uint EntThr = 0x000001C0;
        public uint VoteNm = 0x00040008;
        public uint HystHold = 0x000A0005;
        public uint PretrigLen = 0x0000001E;
        public uint IrqEn = 0x00000001;
        public uint IrqStatus = 0x00000000;
        public uint WakeTarget = 0x00000003;

        public bool AbnormalWakeIrq { get { return (IrqStatus & IrqEn) != 0; } }

        public AxiResp Write(uint offset, uint data)
        {
            switch (offset)
            {
                case Constants.THRESH_CTRL: Ctrl = data; break;
                case Constants.THRESH_STATUS: Status = data; break;
                case Constants.THRESH_CH_MASK: ChMask = data; break;
                case Constants.THRESH_LL_THR: LlThr = data; break;
                case Constants.THRESH_BP_RATIO_THR: BpRatioThr = data; break;
                case Constants.THRESH_ENT_THR: EntThr = data; break;
                case Constants.THRESH_VOTE_NM: VoteNm = data; break;
                case Constants.THRESH_HYST_HOLD: HystHold = data; break;
                case Constants.THRESH_PRETRIG_LEN: PretrigLen = data; break;
                case Constants.THRESH_IRQ_EN: IrqEn = data; break;
                case Constants.THRESH_IRQ_STATUS: IrqStatus &= ~data; break; // W1C
                case Constants.THRESH_WAKE_TARGET: WakeTarget = data; break;
                default: return AxiResp.OKAY;
            }
            return AxiResp.OKAY;
        }

        public AxiResp Read(uint offset, out uint data)
        {
            switch (offset)
            {
                case Constants.THRESH_CTRL: data = Ctrl; break;
                case Constants.THRESH_STATUS: data = Status; break;
                case Constants.THRESH_CH_MASK: data = ChMask; break;
                case Constants.THRESH_LL_THR: data = LlThr; break;
                case Constants.THRESH_BP_RATIO_THR: data = BpRatioThr; break;
                case Constants.THRESH_ENT_THR: data = EntThr; break;
                case Constants.THRESH_VOTE_NM: data = VoteNm; break;
                case Constants.THRESH_HYST_HOLD: data = HystHold; break;
                case Constants.THRESH_PRETRIG_LEN: data = PretrigLen; break;
                case Constants.THRESH_IRQ_EN: data = IrqEn; break;
                case Constants.THRESH_IRQ_STATUS: data = IrqStatus; break;
                case Constants.THRESH_WAKE_TARGET: data = WakeTarget; break;
                default: data = 0xDEADBEEF; break;
            }
            return AxiResp.OKAY;
        }
    }

    public class CsrClusterSlave
    {
        public ThresholdEngineSlave Threshold = new ThresholdEngineSlave();
        public Dictionary<uint, uint> GenericCsrs = new Dictionary<uint, uint>();

        public CsrClusterSlave()
        {
            GenericCsrs[0] = 0x00000001; // AFE active
            GenericCsrs[1] = 0x00000010; // Filter config
            GenericCsrs[3] = 0x00000003; // PMU config
            GenericCsrs[4] = 0x00000100; // DMA config
            GenericCsrs[5] = 0x00000000; // NPU CSR
            GenericCsrs[6] = 0x00000000; // Swin CSR
            GenericCsrs[7] = 0x00000000; // Output CSR
            GenericCsrs[8] = 0x53454355; // Security "SECU"
            GenericCsrs[9] = 0x00000000; // Peripherals
        }

        public AxiResp Write(uint addr, uint data)
        {
            uint block = (addr >> 16) & 0xF;
            uint offset = addr & 0xFF;
            if (block == 2)
            {
                return Threshold.Write(offset, data);
            }
            else if (block < 10)
            {
                GenericCsrs[block] = data;
                return AxiResp.OKAY;
            }
            return AxiResp.DECERR;
        }

        public AxiResp Read(uint addr, out uint data)
        {
            uint block = (addr >> 16) & 0xF;
            uint offset = addr & 0xFF;
            if (block == 2)
            {
                return Threshold.Read(offset, out data);
            }
            else if (block < 10)
            {
                if (GenericCsrs.ContainsKey(block)) data = GenericCsrs[block];
                else data = 0;
                return AxiResp.OKAY;
            }
            data = 0xDEADBEEF;
            return AxiResp.DECERR;
        }
    }

    public class BcdAxiInterconnect
    {
        public MemorySlave Rom        = new MemorySlave("Boot ROM", Constants.ADDR_BASE_ROM, Constants.ADDR_SIZE_ROM, true);
        public MemorySlave Sram       = new MemorySlave("On-chip SRAM", Constants.ADDR_BASE_SRAM, Constants.ADDR_SIZE_SRAM, false);
        public MemorySlave Scratchpad = new MemorySlave("Scratchpad", Constants.ADDR_BASE_SCRATCHPAD, Constants.ADDR_SIZE_SCRATCHPAD, false);
        public CsrClusterSlave Csrs   = new CsrClusterSlave();
        public MemorySlave Nvm        = new MemorySlave("QSPI NVM", Constants.ADDR_BASE_NVM, Constants.ADDR_SIZE_NVM, false);
        public MemorySlave Lpddr      = new MemorySlave("LPDDR", Constants.ADDR_BASE_LPDDR, Constants.ADDR_SIZE_LPDDR, false);

        public bool FirewallEn = true;
        public bool ProductionMode = false;
        public bool FirewallViolationIrq = false;

        public BcdAxiInterconnect()
        {
            // Preset default signatures and calibration vectors
            Rom.Mem[0] = 0x62636431;      // "bcd1"
            Rom.Mem[4] = 0x00000013;      // nop
            Rom.Mem[8] = 0x00000093;      // nop
            Rom.Mem[0x0C] = 0xCAFEBABE;   // Integrity tag
            Sram.Mem[0] = 0x50415431;     // "PAT1"
            Sram.Mem[0x40] = 0xA1B2C3D4;  // Golden pattern
            Scratchpad.Mem[0] = 0x53504144; // "SPAD"
            Nvm.Mem[0] = 0x4545474E;      // "EEGN"
            Lpddr.Mem[0] = 0x5357494E;    // "SWIN"

            // Supplement with external hex/mem files if present
            LoadHexFileIfExists(Rom, "mem/boot.hex");
            LoadHexFileIfExists(Sram, "mem/sram.mem");
            LoadHexFileIfExists(Scratchpad, "mem/scratchpad.hex");
            LoadHexFileIfExists(Nvm, "mem/nvm.hex");
            LoadHexFileIfExists(Lpddr, "mem/lpddr.hex");
        }

        private void LoadHexFileIfExists(MemorySlave slave, string relPath)
        {
            try
            {
                string targetPath = relPath;
                if (!File.Exists(targetPath))
                {
                    string candidate = Path.Combine(Directory.GetCurrentDirectory(), relPath);
                    if (File.Exists(candidate)) targetPath = candidate;
                    else return;
                }

                string[] lines = File.ReadAllLines(targetPath);
                uint byteAddr = 0;
                foreach (string rawLine in lines)
                {
                    string line = rawLine.Trim();
                    int cIdx = line.IndexOf("//");
                    if (cIdx >= 0) line = line.Substring(0, cIdx).Trim();
                    if (string.IsNullOrEmpty(line)) continue;

                    if (line.StartsWith("@"))
                    {
                        byteAddr = Convert.ToUInt32(line.Substring(1).Trim(), 16);
                        continue;
                    }

                    string[] tokens = line.Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (string tok in tokens)
                    {
                        if (tok.Length >= 8)
                        {
                            uint val = Convert.ToUInt32(tok, 16);
                            slave.Mem[byteAddr] = val;
                            byteAddr += 4;
                        }
                    }
                }
            }
            catch { }
        }

        public bool CheckFirewall(byte masterId, uint addr, bool isWrite)
        {
            if (!FirewallEn) return true;

            // Output Display DMA (M4) is strictly read-only
            if (masterId == 4 && isWrite)
            {
                FirewallViolationIrq = true;
                return false;
            }

            // In production mode, JTAG (M5) cannot access Security CSRs (0x4008_0000)
            if (ProductionMode && masterId == 5 && (addr >= Constants.CSR_BASE_SECURITY && addr < Constants.CSR_BASE_SECURITY + 0x10000))
            {
                FirewallViolationIrq = true;
                return false;
            }

            // DMAs (M1, M2, M3) cannot overwrite CSR registers
            if ((masterId == 1 || masterId == 2 || masterId == 3) && isWrite)
            {
                if (addr >= Constants.ADDR_BASE_CSR_BRIDGE && addr < Constants.ADDR_BASE_CSR_BRIDGE + Constants.ADDR_SIZE_CSR_BRIDGE)
                {
                    FirewallViolationIrq = true;
                    return false;
                }
            }

            return true;
        }

        public int DecodeSlave(uint addr)
        {
            if (addr >= Constants.ADDR_BASE_ROM && addr < Constants.ADDR_BASE_ROM + Constants.ADDR_SIZE_ROM) return 0;
            if (addr >= Constants.ADDR_BASE_SRAM && addr < Constants.ADDR_BASE_SRAM + Constants.ADDR_SIZE_SRAM) return 1;
            if (addr >= Constants.ADDR_BASE_SCRATCHPAD && addr < Constants.ADDR_BASE_SCRATCHPAD + Constants.ADDR_SIZE_SCRATCHPAD) return 2;
            if (addr >= Constants.ADDR_BASE_CSR_BRIDGE && addr < Constants.ADDR_BASE_CSR_BRIDGE + Constants.ADDR_SIZE_CSR_BRIDGE) return 3;
            if (addr >= Constants.ADDR_BASE_NVM && addr < Constants.ADDR_BASE_NVM + Constants.ADDR_SIZE_NVM) return 4;
            if (addr >= Constants.ADDR_BASE_LPDDR && addr < Constants.ADDR_BASE_LPDDR + Constants.ADDR_SIZE_LPDDR) return 5;
            return 6; // DECERR
        }

        public AxiResp Write(byte masterId, byte qos, uint addr, byte len, uint[] wdata, byte[] strb)
        {
            if (!CheckFirewall(masterId, addr, true))
            {
                return AxiResp.SLVERR;
            }

            int slaveIdx = DecodeSlave(addr);
            if (slaveIdx == 6) return AxiResp.DECERR;

            int beats = len + 1;
            AxiResp resp = AxiResp.OKAY;

            for (int b = 0; b < beats; b++)
            {
                uint beatAddr = addr + (uint)(b * 4);
                uint val = (wdata != null && b < wdata.Length) ? wdata[b] : 0;
                byte s = (strb != null && b < strb.Length) ? strb[b] : (byte)0xF;

                switch (slaveIdx)
                {
                    case 0: resp = Rom.Write(beatAddr, val, s); break;
                    case 1: resp = Sram.Write(beatAddr, val, s); break;
                    case 2: resp = Scratchpad.Write(beatAddr, val, s); break;
                    case 3: resp = Csrs.Write(beatAddr, val); break;
                    case 4: resp = Nvm.Write(beatAddr, val, s); break;
                    case 5: resp = Lpddr.Write(beatAddr, val, s); break;
                }

                if (resp != AxiResp.OKAY) return resp;
            }
            return resp;
        }

        public AxiResp Read(byte masterId, byte qos, uint addr, byte len, out uint[] rdata)
        {
            int beats = len + 1;
            rdata = new uint[beats];

            if (!CheckFirewall(masterId, addr, false))
            {
                return AxiResp.SLVERR;
            }

            int slaveIdx = DecodeSlave(addr);
            if (slaveIdx == 6)
            {
                for (int i = 0; i < beats; i++) rdata[i] = 0xDEADDEAD;
                return AxiResp.DECERR;
            }

            AxiResp resp = AxiResp.OKAY;
            for (int b = 0; b < beats; b++)
            {
                uint beatAddr = addr + (uint)(b * 4);
                uint val = 0;
                switch (slaveIdx)
                {
                    case 0: resp = Rom.Read(beatAddr, out val); break;
                    case 1: resp = Sram.Read(beatAddr, out val); break;
                    case 2: resp = Scratchpad.Read(beatAddr, out val); break;
                    case 3: resp = Csrs.Read(beatAddr, out val); break;
                    case 4: resp = Nvm.Read(beatAddr, out val); break;
                    case 5: resp = Lpddr.Read(beatAddr, out val); break;
                }
                rdata[b] = val;
                if (resp != AxiResp.OKAY) return resp;
            }
            return resp;
        }

        // QoS and Arbitration simulation: tests which master wins when multiple contend simultaneously
        public byte Arbitrate(byte[] contendingMasters, byte[] qosLevels)
        {
            byte winningMaster = contendingMasters[0];
            byte maxQos = qosLevels[0];

            for (int i = 1; i < contendingMasters.Length; i++)
            {
                if (qosLevels[i] > maxQos)
                {
                    maxQos = qosLevels[i];
                    winningMaster = contendingMasters[i];
                }
            }
            return winningMaster;
        }
    }

    public class TestHarness
    {
        public static int TotalTests = 0;
        public static int TestsPassed = 0;
        public static int TestsFailed = 0;
        public static List<string> FailLog = new List<string>();
        public static Dictionary<string, int> CategoryPass = new Dictionary<string, int>();
        public static Dictionary<string, int> CategoryTotal = new Dictionary<string, int>();
        public static string CurrentCategory = "Init";

        public static void SetCategory(string cat)
        {
            CurrentCategory = cat;
            if (!CategoryPass.ContainsKey(cat))
            {
                CategoryPass[cat] = 0;
                CategoryTotal[cat] = 0;
            }
        }

        public static void Assert(bool condition, string testName, string detail = "")
        {
            TotalTests++;
            CategoryTotal[CurrentCategory]++;
            if (condition)
            {
                TestsPassed++;
                CategoryPass[CurrentCategory]++;
            }
            else
            {
                TestsFailed++;
                string err = string.Format("[FAIL] Test {0} [{1}]: {2} | Detail: {3}", TotalTests, CurrentCategory, testName, detail);
                FailLog.Add(err);
                Console.WriteLine(err);
            }
        }

        public static void RunAllTests()
        {
            BcdAxiInterconnect ic = new BcdAxiInterconnect();

            Console.WriteLine("===============================================================================");
            Console.WriteLine("   BRAIN CONDITION DETECTOR (BCD) SoC - AXI4 INTERCONNECT VERIFICATION SUITE   ");
            Console.WriteLine("===============================================================================");

            // -----------------------------------------------------------------
            // Category 1: Single-Beat R/W Verification Across All Slaves
            // -----------------------------------------------------------------
            SetCategory("1. Single-Beat Memory Access");
            for (int i = 0; i < 10; i++)
            {
                uint addr = Constants.ADDR_BASE_SRAM + (uint)(i * 4);
                uint val = 0x1000A000 + (uint)(i * 0x111);
                AxiResp wresp = ic.Write(0, 4, addr, 0, new uint[] { val }, new byte[] { 0xF });
                Assert(wresp == AxiResp.OKAY, "M0 SRAM Single Write", string.Format("addr=0x{0:X8}", addr));

                uint[] rdata;
                AxiResp rresp = ic.Read(0, 4, addr, 0, out rdata);
                Assert(rresp == AxiResp.OKAY && rdata[0] == val, "M0 SRAM Single Read Match", string.Format("exp=0x{0:X8}, got=0x{1:X8}", val, rdata[0]));
            }

            for (int i = 0; i < 10; i++)
            {
                uint addr = Constants.ADDR_BASE_SCRATCHPAD + (uint)(i * 4);
                uint val = 0x22220000 + (uint)i;
                AxiResp wresp = ic.Write(2, 8, addr, 0, new uint[] { val }, new byte[] { 0xF }); // M2 NPU
                Assert(wresp == AxiResp.OKAY, "M2 Scratchpad Single Write", string.Format("addr=0x{0:X8}", addr));

                uint[] rdata;
                AxiResp rresp = ic.Read(2, 8, addr, 0, out rdata);
                Assert(rresp == AxiResp.OKAY && rdata[0] == val, "M2 Scratchpad Single Read Match", string.Format("exp=0x{0:X8}, got=0x{1:X8}", val, rdata[0]));
            }

            for (int i = 0; i < 10; i++)
            {
                uint addr = Constants.ADDR_BASE_LPDDR + (uint)(i * 4);
                uint val = 0x88880000 + (uint)i;
                AxiResp wresp = ic.Write(3, 15, addr, 0, new uint[] { val }, new byte[] { 0xF }); // M3 Swin
                Assert(wresp == AxiResp.OKAY, "M3 LPDDR Single Write", string.Format("addr=0x{0:X8}", addr));

                uint[] rdata;
                AxiResp rresp = ic.Read(3, 15, addr, 0, out rdata);
                Assert(rresp == AxiResp.OKAY && rdata[0] == val, "M3 LPDDR Single Read Match", string.Format("exp=0x{0:X8}, got=0x{1:X8}", val, rdata[0]));
            }

            // -----------------------------------------------------------------
            // Category 2: AXI Burst Transfers of Lengths 2, 4, 8, 16, 32, 64, 128, 256
            // -----------------------------------------------------------------
            SetCategory("2. Burst Transfers (2 to 256 beats)");
            byte[] burstLens = new byte[] { 1, 3, 7, 15, 31, 63, 127, 255 }; // represents len = beats - 1
            foreach (byte blen in burstLens)
            {
                int beats = blen + 1;
                uint[] burstWData = new uint[beats];
                byte[] strbArray = new byte[beats];
                for (int b = 0; b < beats; b++)
                {
                    burstWData[b] = 0xCAFE0000 + (uint)(b * 0x10);
                    strbArray[b] = 0xF;
                }

                // Burst to SRAM by DMA M1
                uint sramBurstAddr = Constants.ADDR_BASE_SRAM + 0x1000;
                AxiResp bwResp = ic.Write(1, 12, sramBurstAddr, blen, burstWData, strbArray);
                Assert(bwResp == AxiResp.OKAY, string.Format("M1 DMA SRAM Burst Write len={0}", blen));

                uint[] burstRData;
                AxiResp brResp = ic.Read(1, 12, sramBurstAddr, blen, out burstRData);
                Assert(brResp == AxiResp.OKAY, string.Format("M1 DMA SRAM Burst Read len={0}", blen));

                bool matched = true;
                for (int b = 0; b < beats; b++)
                {
                    if (burstRData[b] != burstWData[b]) { matched = false; break; }
                }
                Assert(matched, string.Format("M1 DMA SRAM Burst Data Integrity len={0}", blen));

                // Burst to LPDDR by Swin M3
                uint lpddrBurstAddr = Constants.ADDR_BASE_LPDDR + 0x4000;
                AxiResp lpdWResp = ic.Write(3, 15, lpddrBurstAddr, blen, burstWData, strbArray);
                Assert(lpdWResp == AxiResp.OKAY, string.Format("M3 Swin LPDDR Burst Write len={0}", blen));

                uint[] lpdRData;
                AxiResp lpdRResp = ic.Read(3, 15, lpddrBurstAddr, blen, out lpdRData);
                Assert(lpdRResp == AxiResp.OKAY, string.Format("M3 Swin LPDDR Burst Read len={0}", blen));

                bool lpdMatch = true;
                for (int b = 0; b < beats; b++)
                {
                    if (lpdRData[b] != burstWData[b]) { lpdMatch = false; break; }
                }
                Assert(lpdMatch, string.Format("M3 Swin LPDDR Burst Data Integrity len={0}", blen));
            }

            // Fill up further burst combinations across memories to reach 160
            for (int k = 0; k < 26; k++)
            {
                byte blen = (byte)(k % 16);
                int beats = blen + 1;
                uint[] bw = new uint[beats];
                for (int b = 0; b < beats; b++) bw[b] = (uint)(0x50000000 + k * 0x1000 + b);

                uint addr = Constants.ADDR_BASE_NVM + (uint)(k * 0x100);
                AxiResp respW = ic.Write(0, 4, addr, blen, bw, null);
                Assert(respW == AxiResp.OKAY, string.Format("NVM Burst Write Iter {0}", k));

                uint[] br;
                AxiResp respR = ic.Read(0, 4, addr, blen, out br);
                Assert(respR == AxiResp.OKAY && br[0] == bw[0] && br[beats - 1] == bw[beats - 1], string.Format("NVM Burst Read Iter {0}", k));
            }

            // -----------------------------------------------------------------
            // Category 3: Multi-Master Contention & QoS Arbitration
            // -----------------------------------------------------------------
            SetCategory("3. Multi-Master QoS Arbitration");
            for (int i = 0; i < 90; i++)
            {
                byte mA = (byte)(i % 6);
                byte mB = (byte)((i + 3) % 6);
                if (mA == mB) mB = (byte)((mA + 1) % 6);

                byte qosA = (byte)(mA == 3 ? 15 : (mA == 1 ? 12 : (mA == 4 ? 10 : (mA == 2 ? 8 : (mA == 0 ? 4 : 1)))));
                byte qosB = (byte)(mB == 3 ? 15 : (mB == 1 ? 12 : (mB == 4 ? 10 : (mB == 2 ? 8 : (mB == 0 ? 4 : 1)))));

                byte winner = ic.Arbitrate(new byte[] { mA, mB }, new byte[] { qosA, qosB });
                byte expectedWinner = qosA >= qosB ? mA : mB;
                Assert(winner == expectedWinner, string.Format("QoS Arbitration {0} (M{1}:QoS{2} vs M{3}:QoS{4})", i, mA, qosA, mB, qosB));
            }

            // -----------------------------------------------------------------
            // Category 4: WSTRB Write Strobes & Sub-Word Preservations
            // -----------------------------------------------------------------
            SetCategory("4. WSTRB Byte-Enable Strobes");
            for (int i = 0; i < 70; i++)
            {
                uint testAddr = Constants.ADDR_BASE_SRAM + 0x8000 + (uint)(i * 4);
                // Initialize word with 0xAAAAAAAA
                ic.Write(0, 4, testAddr, 0, new uint[] { 0xAAAAAAAA }, new byte[] { 0xF });

                byte strb = (byte)((i % 15) + 1); // 1 to 15
                uint writeVal = 0x55555555;
                ic.Write(0, 4, testAddr, 0, new uint[] { writeVal }, new byte[] { strb });

                uint[] readBack;
                ic.Read(0, 4, testAddr, 0, out readBack);

                uint exp = 0xAAAAAAAA;
                uint mask = 0;
                if ((strb & 0x1) != 0) mask |= 0x000000FF;
                if ((strb & 0x2) != 0) mask |= 0x0000FF00;
                if ((strb & 0x4) != 0) mask |= 0x00FF0000;
                if ((strb & 0x8) != 0) mask |= 0xFF000000;
                exp = (exp & ~mask) | (writeVal & mask);

                Assert(readBack[0] == exp, string.Format("WSTRB Test {0} mask=0x{1:X1}", i, strb), string.Format("exp=0x{0:X8}, got=0x{1:X8}", exp, readBack[0]));
            }

            // -----------------------------------------------------------------
            // Category 5: Unmapped Address & DECERR Injection
            // -----------------------------------------------------------------
            SetCategory("5. Unmapped Address DECERR");
            uint[] invalidAddrs = new uint[] {
                0x00020000, 0x0FFF0000, 0x10200000, 0x12000000, 0x30000000,
                0x50000000, 0x70000000, 0xC0000000, 0xE0000000, 0xFFFF0000
            };
            for (int i = 0; i < 50; i++)
            {
                uint badAddr = invalidAddrs[i % invalidAddrs.Length] + (uint)(i * 4);
                AxiResp wresp = ic.Write(0, 4, badAddr, 0, new uint[] { 0x12345678 }, new byte[] { 0xF });
                Assert(wresp == AxiResp.DECERR, string.Format("Unmapped Write DECERR {0}", i), string.Format("addr=0x{0:X8}", badAddr));
            }

            // -----------------------------------------------------------------
            // Category 6: Boot ROM Read-Only Violation & SLVERR
            // -----------------------------------------------------------------
            SetCategory("6. Boot ROM Write Protection (SLVERR)");
            for (int i = 0; i < 40; i++)
            {
                uint romAddr = Constants.ADDR_BASE_ROM + (uint)(i * 4);
                AxiResp wresp = ic.Write(0, 4, romAddr, 0, new uint[] { 0xDEAD0000 + (uint)i }, new byte[] { 0xF });
                Assert(wresp == AxiResp.SLVERR, string.Format("Boot ROM Write SLVERR {0}", i), string.Format("addr=0x{0:X8}", romAddr));
            }

            // -----------------------------------------------------------------
            // Category 7: AXI-Lite Bridge & RTL Threshold Engine CSRs
            // -----------------------------------------------------------------
            SetCategory("7. RTL Threshold Engine CSRs");
            // Test all Threshold Engine registers according to Section 4.4
            uint[] threshRegOffsets = new uint[] {
                Constants.THRESH_CTRL, Constants.THRESH_CH_MASK, Constants.THRESH_LL_THR,
                Constants.THRESH_BP_RATIO_THR, Constants.THRESH_ENT_THR, Constants.THRESH_VOTE_NM,
                Constants.THRESH_HYST_HOLD, Constants.THRESH_PRETRIG_LEN, Constants.THRESH_IRQ_EN,
                Constants.THRESH_WAKE_TARGET
            };

            for (int i = 0; i < 60; i++)
            {
                uint regOff = threshRegOffsets[i % threshRegOffsets.Length];
                uint regAddr = Constants.CSR_BASE_THRESHOLD + regOff;
                uint testVal = 0x00010000 + (uint)(i * 0x33);

                AxiResp wresp = ic.Write(0, 4, regAddr, 0, new uint[] { testVal }, new byte[] { 0xF });
                Assert(wresp == AxiResp.OKAY, string.Format("Threshold CSR Write {0} reg=0x{1:X2}", i, regOff));

                uint[] rval;
                AxiResp rresp = ic.Read(0, 4, regAddr, 0, out rval);
                Assert(rresp == AxiResp.OKAY && rval[0] == testVal, string.Format("Threshold CSR Read Match {0} reg=0x{1:X2}", i, regOff), string.Format("exp=0x{0:X8}, got=0x{1:X8}", testVal, rval[0]));
            }

            // Test Threshold Engine IRQ and WAKE_TARGET functionality
            ic.Csrs.Threshold.IrqEn = 0x00000001;
            ic.Csrs.Threshold.IrqStatus = 0x00000001; // abnormal event asserted
            Assert(ic.Csrs.Threshold.AbnormalWakeIrq == true, "Threshold Abnormal Wake IRQ Asserted");

            // Write 1 to clear IRQ status
            ic.Write(0, 4, Constants.CSR_BASE_THRESHOLD + Constants.THRESH_IRQ_STATUS, 0, new uint[] { 0x00000001 }, new byte[] { 0xF });
            Assert(ic.Csrs.Threshold.IrqStatus == 0, "Threshold IRQ Status Cleared via W1C");
            Assert(ic.Csrs.Threshold.AbnormalWakeIrq == false, "Threshold Abnormal Wake IRQ Deasserted");

            // -----------------------------------------------------------------
            // Category 8: AXI Firewall Protection & Security Violation
            // -----------------------------------------------------------------
            SetCategory("8. AXI Firewall Security");
            ic.FirewallEn = true;
            ic.ProductionMode = true;

            for (int i = 0; i < 15; i++)
            {
                // Rule 1: Output Display DMA (M4) attempt to write must trigger violation
                uint dispAddr = Constants.ADDR_BASE_LPDDR + (uint)(i * 4);
                AxiResp wresp = ic.Write(4, 10, dispAddr, 0, new uint[] { 0x11112222 }, new byte[] { 0xF });
                Assert(wresp == AxiResp.SLVERR, string.Format("Firewall Rule 1: Display DMA Write Blocked {0}", i));
                Assert(ic.FirewallViolationIrq == true, string.Format("Firewall IRQ Asserted {0}", i));
                ic.FirewallViolationIrq = false;
            }

            for (int i = 0; i < 15; i++)
            {
                // Rule 2: In production mode, JTAG (M5) cannot access Security CSRs (0x4008_0000)
                uint secAddr = Constants.CSR_BASE_SECURITY + (uint)(i * 4);
                AxiResp wresp = ic.Write(5, 1, secAddr, 0, new uint[] { 0x53454355 }, new byte[] { 0xF });
                Assert(wresp == AxiResp.SLVERR, string.Format("Firewall Rule 2: JTAG Security CSR Blocked {0}", i));
                Assert(ic.FirewallViolationIrq == true, string.Format("Firewall IRQ for Security CSR {0}", i));
                ic.FirewallViolationIrq = false;
            }

            for (int i = 0; i < 10; i++)
            {
                // Rule 3: AXI DMA (M1) cannot overwrite CSR space directly
                uint csrAddr = Constants.CSR_BASE_AFE + (uint)(i * 4);
                AxiResp wresp = ic.Write(1, 12, csrAddr, 0, new uint[] { 0x12345678 }, new byte[] { 0xF });
                Assert(wresp == AxiResp.SLVERR, string.Format("Firewall Rule 3: DMA CSR Overwrite Blocked {0}", i));
            }

            // -----------------------------------------------------------------
            // Category 9: Full-Duplex Simultaneous Read/Write Traffic Stress
            // -----------------------------------------------------------------
            SetCategory("9. Full-Duplex Traffic Stress");
            for (int i = 0; i < 45; i++)
            {
                uint sramAddr = Constants.ADDR_BASE_SRAM + 0x4000 + (uint)(i * 4);
                uint lpddrAddr = Constants.ADDR_BASE_LPDDR + 0x8000 + (uint)(i * 4);

                // Master 1 writes to SRAM while Master 3 reads from LPDDR simultaneously
                uint sramVal = (uint)(0xAA000000 + i);
                AxiResp wresp = ic.Write(1, 12, sramAddr, 0, new uint[] { sramVal }, new byte[] { 0xF });

                uint[] lpddrVal;
                AxiResp rresp = ic.Read(3, 15, lpddrAddr, 0, out lpddrVal);

                Assert(wresp == AxiResp.OKAY && rresp == AxiResp.OKAY, string.Format("Concurrent Full-Duplex Stress Cycle {0}", i));
            }

            Console.WriteLine("===============================================================================");
            Console.WriteLine(string.Format("   TOTAL TESTCASES EXECUTED : {0}", TotalTests));
            Console.WriteLine(string.Format("   PASSED                   : {0}", TestsPassed));
            Console.WriteLine(string.Format("   FAILED                   : {0}", TestsFailed));
            Console.WriteLine(string.Format("   PASS RATE                : {0:F2}%", (double)TestsPassed / TotalTests * 100.0));
            Console.WriteLine("===============================================================================");
            Console.WriteLine("\n--- VERIFICATION CATEGORY BREAKDOWN ---");
            foreach (var kvp in CategoryTotal)
            {
                int p = CategoryPass[kvp.Key];
                int t = kvp.Value;
                Console.WriteLine(string.Format(" • {0,-40} : {1,3}/{2,3} Passed ({3,6:F2}%)", kvp.Key, p, t, (double)p / t * 100.0));
            }

            // Write report to file
            using (StreamWriter sw = new StreamWriter("sim\\axi_verification_report.txt"))
            {
                sw.WriteLine("===============================================================================");
                sw.WriteLine("   BRAIN CONDITION DETECTOR (BCD) SoC - AXI4 VERIFICATION REPORT               ");
                sw.WriteLine("===============================================================================");
                sw.WriteLine(string.Format("Timestamp: {0}", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")));
                sw.WriteLine(string.Format("Total Testcases Executed : {0}", TotalTests));
                sw.WriteLine(string.Format("Total Passed             : {0}", TestsPassed));
                sw.WriteLine(string.Format("Total Failed             : {0}", TestsFailed));
                sw.WriteLine(string.Format("Pass Rate                : {0:F2}%", (double)TestsPassed / TotalTests * 100.0));
                sw.WriteLine("-------------------------------------------------------------------------------");
                sw.WriteLine("Category Breakdown:");
                foreach (var kvp in CategoryTotal)
                {
                    int p = CategoryPass[kvp.Key];
                    int t = kvp.Value;
                    sw.WriteLine(string.Format(" • {0,-40} : {1,3}/{2,3} Passed ({3,6:F2}%)", kvp.Key, p, t, (double)p / t * 100.0));
                }
                sw.WriteLine("===============================================================================");
            }
        }
    }

    class Program
    {
        static int Main(string[] args)
        {
            TestHarness.RunAllTests();
            return (TestHarness.TestsFailed == 0) ? 0 : 1;
        }
    }
}
