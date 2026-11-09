library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SPI_master is
  generic(
    G_DUMMY_BITS      : integer; -- number of dummy bits to be transmitted before the data bits
    G_DATA_BITS       : integer; -- number of data bits to be transmitted
    G_CHIP_NUM        : integer; -- number of chip selects
    G_SYSTEM_CLK_FREQ : integer; -- system clock frequency in Hz
    G_BAUD_RATE       : integer;
    G_IDLE_BIT        : std_logic -- idle bit used to fill both shift registers.
  );
  port (
    I_CLK             : in std_logic;
    I_ASYNC_RST       : in std_logic;
    I_TX_BYTE         : in std_logic_vector((G_DATA_BITS-1) downto 0);
    I_CS_SWITCH       : in std_logic_vector(G_CHIP_NUM downto 1);
    I_CPOL            : in std_logic;
    I_CPHA            : in std_logic;

    --master to slave
    I_RX_READY        : in  std_logic; -- slave is ready to receive data from master
    O_TX_VALID        : out std_logic;
    O_TX_LAST         : out std_logic;
    O_MOSI            : out std_logic;

    --slave to master
    O_TX_READY        : out std_logic; -- master is ready to receive data from slave
    I_RX_VALID        : in  std_logic;
    I_RX_LAST         : in  std_logic;
    I_MISO            : in  std_logic;

    O_SCLK            : out std_logic;
    O_CS_SWITCH       : out std_logic_vector(G_CHIP_NUM downto 1);
    O_RX_BYTE         : out std_logic_vector((G_DATA_BITS-1) downto 0)
  );
end entity SPI_master;

architecture rtl of SPI_master is

  constant c_all_idle           : std_logic_vector(I_TX_BYTE'range) := (others => G_IDLE_BIT);

  signal spi_mode               : natural;

  signal bit_count_m_rx         : integer range 0 to (G_DUMMY_BITS + G_DATA_BITS+3);
  signal bit_count_m_tx         : integer range 0 to (G_DATA_BITS+1);

  signal cs_active              : integer range 1 to G_CHIP_NUM;

  signal tx_valid               : std_logic;
  signal tx_last                : std_logic;

  signal mosi                   : std_logic;
  signal mosi_shr               : std_logic_vector((G_DATA_BITS-1) downto 0):= (others => '0');
  signal miso_shr               : std_logic_vector((G_DATA_BITS-1) downto 0):= (others => '0');

  signal master_falling_edge    : std_logic;
  signal master_rising_edge     : std_logic;
  signal master_sample_edge     : std_logic;
  signal master_shift_out_edge  : std_logic;

  signal sclk_pulse             : std_logic;
  signal sclk_pulse_delayed     : std_logic;
  signal sclk_period_count      : integer range 0 to ((G_SYSTEM_CLK_FREQ/G_BAUD_RATE)-1) := 0;

  type t_master_mosi_state_next is (s_master_to_slave_idle, s_master_to_slave_transmitting, s_master_to_slave_transmitted, s_master_to_slave_holding);
  signal master_mosi_state_next : t_master_mosi_state_next;

  type t_master_miso_state_next is (s_slave_to_master_idle, s_slave_to_master_sampling_dummy, s_slave_to_master_sampling_valid, s_slave_to_master_sampled_valid, s_slave_to_master_holding_dummy, s_slave_to_master_holding_valid);
  signal master_miso_state_next : t_master_miso_state_next;
begin

  O_SCLK      <= sclk_pulse;
  O_CS_SWITCH <= I_CS_SWITCH;
  O_MOSI      <= mosi;
  O_TX_VALID  <= tx_valid;
  O_TX_LAST   <= tx_last;
  O_TX_READY  <=  '1' when  (master_miso_state_next = s_slave_to_master_sampling_dummy) or 
                            (master_miso_state_next = s_slave_to_master_sampling_valid) or 
                            (master_mosi_state_next = s_master_to_slave_transmitted) else 
                  '0';
  O_RX_BYTE   <=  miso_shr when (master_miso_state_next = s_slave_to_master_sampled_valid) else 
                  (others => G_IDLE_BIT);

  EDGE_DET_PROC: process(I_ASYNC_RST, I_CLK)
  begin
    if (I_ASYNC_RST = '1') then
      master_rising_edge  <= '0';
      master_falling_edge <= '0';
    elsif rising_edge(I_CLK) then
      if ((sclk_pulse = '1') and (sclk_pulse_delayed = '0')) then
        master_rising_edge  <= '1';
        master_falling_edge <= '0';
      elsif ((sclk_pulse = '0') and (sclk_pulse_delayed = '1')) then
        master_rising_edge  <= '0';
        master_falling_edge <= '1';
      else
        master_rising_edge  <= '0';
        master_falling_edge <= '0';
      end if;
    end if;
  end process;

  SPI_MODE_DET_PROC: process(I_CPOL, I_CPHA) is
  begin
    if (I_CPOL = '0') and (I_CPHA = '0') then 
      spi_mode <= 0;
    elsif (I_CPOL = '0') and (I_CPHA = '1') then 
      spi_mode <= 1;
    elsif (I_CPOL = '1') and (I_CPHA = '0') then 
      spi_mode <= 2;
    elsif (I_CPOL = '1') and (I_CPHA = '1') then 
      spi_mode <= 3;
    end if; 
  end process;

  SPI_MODE_SEL_PROC: process(spi_mode, master_rising_edge, master_falling_edge) is 
  begin
    case (spi_mode) is
    when 0 =>
      -- sclk = 0 on start
      -- sampled before 1st transmit
      master_sample_edge    <= master_rising_edge;
      -- full bit period count before shifting
      master_shift_out_edge <= master_falling_edge;

    when 1 =>
      -- sclk = 0 on start
      -- sampled after 1st transmit
      master_sample_edge    <= master_falling_edge;
      -- half bit period count before shifting
      master_shift_out_edge <= master_rising_edge;

    when 2 =>
      -- sclk = 1 on start
      -- sampled before 1st transmit
      master_sample_edge    <= master_falling_edge;
      -- half bit period count before shifting
      master_shift_out_edge <= master_rising_edge;

    when 3 =>
      -- sclk = 1 on start
      -- sampled after 1st transmit
      master_sample_edge    <= master_rising_edge;
      -- full bit period count before shifting
      master_shift_out_edge <= master_falling_edge;

    when others =>
      null;
      
    end case;
  end process;

  SCLK_GEN_PROC: process(I_ASYNC_RST, I_CLK) is
  begin
    if (I_ASYNC_RST = '1') then
      sclk_period_count  <= 0;
      sclk_pulse         <= I_CPOL;
      sclk_pulse_delayed <= I_CPOL;
    elsif rising_edge(I_CLK) then
      sclk_pulse          <= I_CPOL; -- set sclk_pulse to the value of I_CPOL when cs is inactive
      sclk_pulse_delayed  <= sclk_pulse;

      --clk generation
      if ((I_CS_SWITCH(cs_active)) = '0') then
        if (sclk_period_count = ((G_SYSTEM_CLK_FREQ/G_BAUD_RATE)-1)) then
          sclk_period_count  <= 0;
          sclk_pulse         <= not sclk_pulse;
          sclk_pulse_delayed <= sclk_pulse;
        else
          sclk_period_count  <= (sclk_period_count + 1);
          sclk_pulse         <= sclk_pulse;
        end if;
      end if;
    end if;
  end process;

  CS_DET_PROC: process(I_CLK) is 
    variable v_cs_active : integer range 1 to G_CHIP_NUM;
  begin
    if rising_edge(I_CLK) then
      for i in 1 to G_CHIP_NUM loop
        if (I_CS_SWITCH(i) = '0') then
          v_cs_active := i;
          cs_active   <= v_cs_active;
        end if;
      end loop;
    end if;
  end process;

  MOSI_PROC: process(I_ASYNC_RST, I_CLK) is
  begin
    if (I_ASYNC_RST = '1') then
      master_mosi_state_next <= s_master_to_slave_idle;
      bit_count_m_tx         <= 0;
      mosi_shr               <= (others => '0');
      mosi                   <= G_IDLE_BIT;
      tx_valid               <= '0';
      tx_last                <= '0';
    elsif rising_edge(I_CLK) then
      case (master_mosi_state_next) is
        when (s_master_to_slave_idle) =>
          mosi_shr        <= (others => '0');
          mosi            <= G_IDLE_BIT;
          bit_count_m_tx  <= 0;
          tx_last         <= '0';

          if (I_TX_BYTE /= c_all_idle) then
            tx_valid <= '1';
            mosi_shr <= I_TX_BYTE; -- load mosi_shr with the data to be transmitted
          else
            tx_valid <= '0';
          end if; 

          if (I_CS_SWITCH(cs_active) = '0') and (I_RX_READY = '1') and (tx_valid = '1') then
            master_mosi_state_next <= s_master_to_slave_transmitting;
            mosi_shr               <= I_TX_BYTE; -- load mosi_shr with the data to be transmitted
          end if;

        when (s_master_to_slave_transmitting) =>
          if ((spi_mode = 0) or (spi_mode = 2)) then
            if (I_CS_SWITCH(cs_active) = '0') and (I_RX_READY = '1') and (tx_valid = '1') then
              if (bit_count_m_tx = G_DATA_BITS + 1) then
                tx_last                 <= '1'; -- set tx_last to 1 when the last bit of data is transmitted
                mosi                    <= G_IDLE_BIT; -- set mosi to idle bit when the last bit of data is transmitted
                bit_count_m_tx          <= 0;
                master_mosi_state_next  <= s_master_to_slave_transmitted;
              else
                -- mosi <= mosi_shr(mosi_shr'left);
                if (master_shift_out_edge = '1') then                     -- shift out the leftmost bit of mosi_shr
                  mosi           <= mosi_shr(mosi_shr'left);
                  mosi_shr       <= mosi_shr(((mosi_shr'left) - 1) downto 0) & G_IDLE_BIT; -- shift MOSI left and fill with 0
                  bit_count_m_tx <= (bit_count_m_tx + 1);
                end if;
              end if;
            -- go inactive state if cs is inactive, tx_valid is '0', or rx_ready is '0' and there are still bits to transmit
            elsif ((I_CS_SWITCH(cs_active) = '1') or (I_RX_READY = '0')) and (bit_count_m_tx < G_DATA_BITS + 1) then
              master_mosi_state_next <= s_master_to_slave_holding;
              mosi_shr               <= mosi_shr;       -- hold the current mosi_shr value
              bit_count_m_tx         <= bit_count_m_tx; -- hold the current bit_count_m_tx value
            end if;
          else
            if (I_CS_SWITCH(cs_active) = '0') and (I_RX_READY = '1') and (tx_valid = '1') then
              if (bit_count_m_tx = G_DATA_BITS + 1) then
                tx_last                 <= '1'; -- set tx_last to 1 when the last bit of data is transmitted
                mosi                    <= G_IDLE_BIT; -- set mosi to idle bit when the last bit of data is transmitted
                bit_count_m_tx          <= 0;
                master_mosi_state_next  <= s_master_to_slave_transmitted;
              else
                mosi <= mosi_shr(mosi_shr'left);
                if (master_shift_out_edge = '1') then                     -- shift out the leftmost bit of mosi_shr
                  mosi_shr       <= mosi_shr(((mosi_shr'left) - 1) downto 0) & G_IDLE_BIT; -- shift MOSI left and fill with 0
                  bit_count_m_tx <= (bit_count_m_tx + 1);
                end if;
              end if;
            -- go inactive state if cs is inactive, tx_valid is '0', or rx_ready is '0' and there are still bits to transmit
            elsif ((I_CS_SWITCH(cs_active) = '1') or (I_RX_READY = '0')) and (bit_count_m_tx < G_DATA_BITS + 1) then
              master_mosi_state_next <= s_master_to_slave_holding;
              mosi_shr               <= mosi_shr;       -- hold the current mosi_shr value
              bit_count_m_tx         <= bit_count_m_tx; -- hold the current bit_count_m_tx value
            end if;
          end if;

        when (s_master_to_slave_holding) =>
        -- if cs is active, rx_ready is '1', and tx_valid is '1', go back to transmitting state
          if (I_CS_SWITCH(cs_active) = '0') and (I_RX_READY = '1') then
            master_mosi_state_next <= s_master_to_slave_transmitting;
            mosi_shr               <= mosi_shr;
            bit_count_m_tx         <= bit_count_m_tx;
          else
            master_mosi_state_next <= s_master_to_slave_holding;
            mosi_shr               <= mosi_shr;
            bit_count_m_tx         <= bit_count_m_tx;
          end if;

        when (s_master_to_slave_transmitted) =>
          tx_valid <= '0';
          if (I_RX_LAST = '1') then
            master_mosi_state_next <= s_master_to_slave_idle;
          else
            master_mosi_state_next <= s_master_to_slave_transmitted;
          end if;

        when others =>
          master_mosi_state_next <= s_master_to_slave_idle;

      end case;
    end if;
  end process MOSI_PROC;

  MISO_PROC: process(I_ASYNC_RST, I_CLK) is
  begin
    if (I_ASYNC_RST = '1') then
      master_miso_state_next <= s_slave_to_master_idle;
      bit_count_m_rx         <= 0;
      miso_shr               <= (others => '0');
    elsif rising_edge(I_CLK) then
      case master_miso_state_next is
        when (s_slave_to_master_idle) =>
          bit_count_m_rx <= 0;
          miso_shr       <= (others => '0');
          if (I_CS_SWITCH(cs_active) = '0') and (I_RX_VALID = '1') then
            master_miso_state_next <= s_slave_to_master_sampling_dummy;
          end if;

        when (s_slave_to_master_sampling_dummy) =>
          -- if spi_mode = 0 or 2 sample G_DUMMY_BITS + 1 as samples a bit before a bit has been transmitted along the MOSI line
          if ((spi_mode = 0) or (spi_mode = 2)) then 
            if (I_CS_SWITCH(cs_active) = '0') and (I_RX_VALID = '1') then
              if (tx_last = '1') then
                master_miso_state_next <= s_slave_to_master_sampling_valid;
                bit_count_m_rx         <= bit_count_m_rx;
              else
                master_miso_state_next <= s_slave_to_master_sampling_dummy;
                if (master_sample_edge = '1') then
                  miso_shr       <= miso_shr((miso_shr'left)-1 downto 0) & I_MISO; -- shift in the miso data on the leading edge of sclk MSB first
                  bit_count_m_rx <= bit_count_m_rx + 1;
                end if;
              end if;
            -- if cs is inactive or rx_valid is '0' and the number of bits received is less than the number of dummy bits, go to holding dummy state
            elsif ((I_CS_SWITCH(cs_active) = '1') or (I_RX_VALID = '0')) and (bit_count_m_rx < (G_DUMMY_BITS + 1)) then
              master_miso_state_next <= s_slave_to_master_holding_dummy;
              miso_shr               <= miso_shr;       -- hold the current miso_shr value
              bit_count_m_rx         <= bit_count_m_rx; -- hold the current miso_shr and bit_count_m_rx values
            end if;
          else
            if (I_CS_SWITCH(cs_active) = '0') and (I_RX_VALID = '1') then
              if (tx_last = '1') then
                master_miso_state_next <= s_slave_to_master_sampling_valid;
                miso_shr               <= miso_shr;
                bit_count_m_rx         <= bit_count_m_rx;
              -- master_miso_state_next <= s_slave_to_master_sampling_dummy;
              else
                master_miso_state_next <= s_slave_to_master_sampling_dummy;
                if (master_sample_edge = '1') then
                  miso_shr       <= miso_shr((miso_shr'left)-1 downto 0) & I_MISO; -- shift in the miso data on the leading edge of sclk MSB first
                  bit_count_m_rx <= bit_count_m_rx + 1;
                end if;
              end if;
            -- if cs is inactive or rx_valid is '0' and the number of bits received is less than the number of dummy bits, go to holding dummy state
            elsif ((I_CS_SWITCH(cs_active) = '1') or (I_RX_VALID = '0')) and (bit_count_m_rx < (G_DUMMY_BITS + 1)) then
              master_miso_state_next <= s_slave_to_master_holding_dummy;
              miso_shr               <= miso_shr;       -- hold the current miso_shr value
              bit_count_m_rx         <= bit_count_m_rx; -- hold the current miso_shr and bit_count_m_rx values
            end if;
          end if;

        when (s_slave_to_master_sampling_valid) =>
          if (I_CS_SWITCH(cs_active) = '0') and (I_RX_VALID = '1') then
            if (I_RX_LAST = '1') then
              master_miso_state_next <= s_slave_to_master_sampled_valid;
              bit_count_m_rx         <= 0;
            elsif (bit_count_m_rx = (G_DUMMY_BITS + G_DATA_BITS+1)) then --or bit_count_m_rx = (G_DUMMY_BITS + G_DATA_BITS+3) then
              miso_shr               <= miso_shr;
              bit_count_m_rx         <= bit_count_m_rx;
            else
              if (master_sample_edge = '1') then
                miso_shr       <= miso_shr((miso_shr'left)-1 downto 0) & I_MISO; -- shift in the miso data on the leading edge of sclk MSB first
                bit_count_m_rx <= bit_count_m_rx + 1;
              end if;
            end if;    
          elsif ((I_CS_SWITCH(cs_active) = '1') or (I_RX_VALID = '0')) and (bit_count_m_rx < (G_DUMMY_BITS + G_DATA_BITS+1)) then
            master_miso_state_next <= s_slave_to_master_holding_valid;
            miso_shr               <= miso_shr;       -- hold the current miso_shr value
            bit_count_m_rx         <= bit_count_m_rx; -- hold the current bit_count_m_rx value
          end if;

        when (s_slave_to_master_sampled_valid) =>
          master_miso_state_next <= s_slave_to_master_idle;

        when (s_slave_to_master_holding_dummy) =>
          -- if cs is active and rx_valid is '1', go back to sampling dummy state
          if (I_CS_SWITCH(cs_active) = '0') and (I_RX_VALID = '1') then
            master_miso_state_next <= s_slave_to_master_sampling_dummy;
            miso_shr               <= miso_shr;
            bit_count_m_rx         <= bit_count_m_rx;
          else
            master_miso_state_next <= s_slave_to_master_holding_dummy;
            miso_shr               <= miso_shr;
            bit_count_m_rx         <= bit_count_m_rx;
          end if;

        when (s_slave_to_master_holding_valid) =>
          -- if cs is active and rx_valid is '1', go back to sampling valid state
          if (I_CS_SWITCH(cs_active) = '0') and (I_RX_VALID = '1') then
            master_miso_state_next <= s_slave_to_master_sampling_valid;
            miso_shr               <= miso_shr;
            bit_count_m_rx         <= bit_count_m_rx;
          else
            master_miso_state_next <= s_slave_to_master_holding_valid;
            miso_shr               <= miso_shr;
            bit_count_m_rx         <= bit_count_m_rx;
          end if;

        when others =>
          master_miso_state_next <= s_slave_to_master_idle;

      end case;
    end if;     
  end process MISO_PROC;

end architecture;