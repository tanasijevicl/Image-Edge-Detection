library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library xil_defaultlib;
use xil_defaultlib.definitions_PK.all;

-- Implementation of the shift register as a circular buffer (FIFO)
-- Data is stored in RAM memory (probably implemented in BRAM)

entity shift_reg is
	generic (
        G_DATA_WIDTH      : natural := 8;     -- Data width
        G_REG_WIDTH       : natural := 16;    -- Register width (active_width)
		G_SHIFT_REG_WIDTH : natural := 512    -- Shift register width
	);
    port(
        clk      : in std_logic;    -- Clock
        reset    : in std_logic;    -- Reset pointers
        shift_en : in std_logic;    -- Shift enable
        
        active_width : in std_logic_vector(G_REG_WIDTH-1 downto 0);   -- Used part of the shift register
        data_in : in std_logic_vector(G_DATA_WIDTH-1 downto 0);       -- Input data
        data_out : out std_logic_vector(G_DATA_WIDTH-1 downto 0)      -- Output data
    );
end shift_reg;

architecture rtl of shift_reg is
    signal ram_out : std_logic_vector(G_DATA_WIDTH-1 downto 0);  -- RAM output
    
    signal wr_ptr : std_logic_vector((clogb2(G_SHIFT_REG_WIDTH)-1) downto 0) := (others => '0');   -- Write pointer (address)
    signal rd_ptr : std_logic_vector((clogb2(G_SHIFT_REG_WIDTH)-1) downto 0) := (others => '0');   -- Read pointer (address)
    
    signal shift_en_d     : std_logic;                                  -- Delayed shift_en signal   
    signal data_loss      : std_logic;                                  -- Data loss indicator
    signal data_loss_d    : std_logic;                                  -- Delayed data loss indicator                                 
    signal data_out_loss1 : std_logic_vector(G_DATA_WIDTH-1 downto 0);  -- First "lost" data
    signal data_out_loss2 : std_logic_vector(G_DATA_WIDTH-1 downto 0);  -- Second "lost" data
    
    -- Debug
    attribute mark_debug : string;
    attribute mark_debug of wr_ptr   : signal is "true";
    attribute mark_debug of rd_ptr   : signal is "true";  
    attribute mark_debug of data_in  : signal is "true";
    attribute mark_debug of ram_out  : signal is "true";
    attribute mark_debug of data_out : signal is "true";
    
begin
    -- RAM component instance
    RAM: entity work.ram(Behavioral)
        generic map (
            G_RAM_WIDTH       => G_DATA_WIDTH,
            G_RAM_DEPTH       => G_SHIFT_REG_WIDTH,
            G_RAM_PERFORMANCE => "HIGH_PERFORMANCE",
            G_RAM_INIT_FILE   => ""
        )
        port map (
            addra  => wr_ptr,
            addrb  => rd_ptr,
            dina   => data_in,
            clka   => clk,
            wea    => shift_en,
            enb    => '1',
            rstb   => '0',
            regceb => '1',
            doutb  => ram_out
        );

    -- Incrementing read and write pointer (addresses)
    -- Read pointer is "delayed" relative to the write pointer by (active_width + 1) + 2
    -- Plus 2 because of RAM is used in HIGH_PERFORMANCE mode (2 clock cycle read latency)
    SHIFT_PROC: process(clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
                wr_ptr <= (others => '0');
                rd_ptr <= (others => '0');
            else
                if (shift_en = '1') then
                    wr_ptr <= std_logic_vector((unsigned(wr_ptr) + 1) mod G_SHIFT_REG_WIDTH);
                    rd_ptr <= std_logic_vector(to_unsigned((to_integer(unsigned(wr_ptr)) - to_integer(unsigned(active_width)) + 3) 
                                               mod G_SHIFT_REG_WIDTH, clogb2(G_SHIFT_REG_WIDTH)));
                end if;
            end if;
        end if;
    end process SHIFT_PROC;
    
    -- Saving ram output in case of stopped shifting
    DATA_OUT_LOSS_PROC: process(clk) is
    begin
        if (rising_edge(clk)) then
            -- Save data from ram output when shift_en falling edge is detected
            if (shift_en_d = '1' and shift_en = '0') then
                data_out_loss1 <= ram_out;
            end if;
            -- Save data from ram output when data_loss rising edge is detected
            if (data_loss_d = '0' and data_loss = '1') then
                data_out_loss2 <= ram_out;
            end if;
        end if;
    end process DATA_OUT_LOSS_PROC;
    
    SHIFT_EN_D_PROC: process(clk) is
    begin
        if (rising_edge(clk)) then
            shift_en_d <= shift_en;
        end if;
    end process SHIFT_EN_D_PROC;
    
    -- Indication of potential data loss from ram output
    DATA_LOSS_PROC: process(clk) is
    begin
        if (rising_edge(clk)) then
            if (shift_en = '1') then
                data_loss <= '0';
            else
                data_loss <= '1';
            end if;
            data_loss_d <= data_loss;
        end if;
    end process DATA_LOSS_PROC;
    
    -- Forwarding data from ram output or recovering data from data_out_loss buffers
    DATA_OUT_PROC: process(ram_out, data_out_loss1, data_out_loss2, data_loss, data_loss_d) is
    begin
        if (data_loss_d = '1' and data_loss = '0') then
            data_out <= data_out_loss2;
        elsif (data_loss = '1') then
            data_out <= data_out_loss1;
        else
            data_out <= ram_out;
        end if;
    end process DATA_OUT_PROC;
    
end rtl; -- of shift_reg