module SignalMarket.Server.Config
  ( AppConfig(..)
  , mkAppConfig
    -- * ReExports
  , module SignalMarket.Server.Config.Utils
  , Contracts(..)
  , DeployReceipt(..)

  ) where

import           Data.String.Conversions          (cs)
import           Network.Ethereum.Api.Provider    (Provider (..))
import           Network.HTTP.Client              (Manager)
import           Network.HTTP.Client.TLS          (newTlsManager)
import           SignalMarket.Server.Config.Node  (getNetworkID)
import           SignalMarket.Server.Config.Types (Contracts (..),
                                                   DeployReceipt (..),
                                                   mkContracts)
import           SignalMarket.Server.Config.Utils (getEnvVarWithDefault,
                                                   makeConfig)

data AppConfig = AppConfig
  { appCfgContracts   :: Contracts
  , appCfgWeb3Manager :: (Provider, Manager)
  }

mkAppConfig :: IO AppConfig
mkAppConfig = do
  provider <- makeConfig $
    HttpProvider <$> getEnvVarWithDefault "NODE_URL" "http://localhost:8545"
  web3Mgr <- newTlsManager
  networkID <- makeConfig $ cs <$> getNetworkID web3Mgr provider
  contracts <- makeConfig $ mkContracts networkID
  return $ AppConfig
    { appCfgContracts = contracts
    , appCfgWeb3Manager = (provider, web3Mgr)
    }
