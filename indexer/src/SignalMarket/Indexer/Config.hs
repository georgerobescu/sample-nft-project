module SignalMarket.Indexer.Config

  ( IndexerConfig(..)
  , mkIndexerConfig
    -- * ReExports
  , Contracts(..)
  , DeployReceipt(..)

  ) where

import           Control.Lens                       (lens)
import           Data.String.Conversions            (cs)
import           Network.Ethereum.Api.Provider      (Provider (..))
import           Network.HTTP.Client                (Manager)
import           Network.HTTP.Client.TLS            (newTlsManager)
import           SignalMarket.Common.Config.Logging (HasLogConfig (..),
                                                     LogConfig)
import           SignalMarket.Common.Config.Node    (getNetworkID)
import           SignalMarket.Common.Config.Types   (Contracts (..),
                                                     DeployReceipt (..),
                                                     mkContracts)
import           SignalMarket.Common.Config.Utils   (getEnvVarWithDefault,
                                                     makeConfig)

data IndexerConfig = IndexerConfig
  { indexerCfgContracts   :: Contracts
  , indexerCfgWeb3Manager :: (Provider, Manager)
  , indexerLogConfig      :: LogConfig
  }

mkIndexerConfig :: LogConfig -> IO IndexerConfig
mkIndexerConfig lc = do
  provider <- makeConfig $
    HttpProvider <$> getEnvVarWithDefault "NODE_URL" "http://localhost:8545"
  web3Mgr <- newTlsManager
  networkID <- makeConfig $ cs <$> getNetworkID web3Mgr provider
  contracts <- makeConfig $ mkContracts networkID
  return $ IndexerConfig
    { indexerCfgContracts = contracts
    , indexerCfgWeb3Manager = (provider, web3Mgr)
    , indexerLogConfig = lc
    }

instance HasLogConfig IndexerConfig where
  logConfig = lens g s
    where
      g = indexerLogConfig
      s cfg lc = cfg {indexerLogConfig = lc}
