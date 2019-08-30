module SignalMarketSpec (spec) where

import Prelude

import Chanterelle.Internal.Deploy (DeployReceipt)
import Chanterelle.Internal.Types (NoArgs)
import Chanterelle.Test (TestConfig, assertWeb3, takeEvent)
import Contracts.FoamToken as FoamToken
import Contracts.SignalMarket as SignalMarket
import Contracts.SignalToken as SignalToken
import Control.Parallel (parTraverse_)
import Data.Array ((!!))
import Data.ByteString as BS
import Data.Either (Either(..))
import Data.Lens ((?~))
import Data.Maybe (Maybe(..), fromJust)
import Data.Tuple (Tuple(..))
import Effect.Aff (Aff)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (liftEffect)
import Effect.Class.Console (log)
import Main (SignalMarket, SignalToken)
import Network.Ethereum.Core.HexString (mkHexString)
import Network.Ethereum.Web3 (class KnownSize, Address, BytesN, CallError, ChainCursor(..), DLProxy, HexString, Provider, TransactionReceipt(..), TransactionStatus(..), UIntN, Web3, _from, _gas, _to, defaultTransactionOptions, embed, fromByteString, mkAddress, uIntNFromBigNumber, unUIntN)
import Network.Ethereum.Web3.Solidity.Sizes (s256, s32)
import Partial.Unsafe (unsafeCrashWith, unsafePartial, unsafePartialBecause)
import Test.Spec (SpecT, beforeAll_, describe, it, pending')
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Type.Proxy (Proxy(..))
import Utils (awaitTxSuccess)

unsafeFromJust :: forall a. String -> Maybe a -> a
unsafeFromJust msg = case _ of
  Nothing -> unsafeCrashWith $ "unsafeFromJust: " <> msg
  Just a -> a

assertStorageCall
  :: forall m a.
     MonadAff m
  => Provider
  -> Web3 (Either CallError a)
  -> m a
assertStorageCall p f = liftAff do
  eRes <- assertWeb3 p f
  case eRes of
    Right x -> pure x
    Left err -> unsafeCrashWith $
                "expected Right in `assertStorageCall`, got error" <> show err

mkUIntN
  :: forall n.
     KnownSize n
  => DLProxy n
  -> Int
  -> UIntN n
mkUIntN p n = unsafePartialBecause "I know how to make a UInt" $
              fromJust $ uIntNFromBigNumber p $ embed n

mkBytesN
  :: forall n.
     KnownSize n
     => DLProxy n
  -> String
  -> BytesN n
mkBytesN p s = unsafePartialBecause "I know how to make Bytes" $
               fromJust $ fromByteString p =<< flip BS.fromString BS.Hex s

faucet
  :: { recipient :: Address
     , foamToken :: Address
     , tokenFaucet :: Address
     }
  -> Web3 HexString
faucet { recipient, foamToken, tokenFaucet } =
  let txOpts = defaultTransactionOptions # _to ?~ foamToken
                                         # _from ?~ tokenFaucet
  in FoamToken.transfer txOpts { _to: recipient
                               , _value: mkUIntN s256 1000000
                               }

spec
  :: forall r .
     TestConfig ( foamToken :: DeployReceipt NoArgs
                , signalToken :: DeployReceipt SignalToken
                , tokenFaucet :: Address
                , signalMarket :: DeployReceipt SignalMarket | r)
  -> SpecT Aff Unit Aff Unit
spec { provider
     , accounts
     , foamToken: {deployAddress: foamToken}
     , signalToken: {deployAddress: signalToken}
     , signalMarket: {deployAddress: signalMarket}
     , tokenFaucet
     } = do
  describe "interact with signal market" do
    -- set up 2 accounts
    -- give tokens to each of them (via faucet)
    let zeroAddr = unsafeFromJust "Must be valid Address 000..." $
                   mkAddress =<< mkHexString "0x0000000000000000000000000000000000000000"
        account1 = unsafePartial $ fromJust $ accounts !! 1
        account2 = unsafePartial $ fromJust $ accounts !! 2
        txOpts1 = defaultTransactionOptions # _from ?~ account1
                                            # _gas ?~ embed 8000000
    beforeAll_ (do
        flip parTraverse_ [account1, account2] \recipient -> do
          txHash <- assertWeb3 provider $ faucet { recipient, foamToken, tokenFaucet }
          awaitTxSuccess txHash provider
      ) $ do
      it "can run the faucet" do
        let txOpts = defaultTransactionOptions # _to ?~ foamToken
        a1balance <- assertStorageCall provider $
                     FoamToken.balanceOf txOpts Latest { _owner: account1 }
        a2balance <- assertStorageCall provider $
                     FoamToken.balanceOf txOpts Latest { _owner: account2 }
        unUIntN a1balance `shouldSatisfy` (_ > zero)
        unUIntN a2balance `shouldSatisfy` (_ > zero)
      -- -- you need to approve some tokens before this
      -- -- then use mint
      -- it "can make a signal token (ERC-721)" do
      --   -- approval process
      --   -- @NOTE: `_gas` sets the max amount the user is willing to pay
      --   let txOpts = defaultTransactionOptions # _to ?~ foamToken
      --                                          # _from ?~ account1
      --                                          # _gas ?~ embed 8000000
      --       approvalAmount = mkUIntN s256 100
      --       approveAction = FoamToken.approve txOpts { _spender: signalToken
      --                                                , _value: approvalAmount
      --                                                }
      --   Tuple _ (FoamToken.Approval appr) <- assertWeb3 provider $
      --     takeEvent (Proxy :: Proxy FoamToken.Approval) foamToken approveAction
      --   appr.value `shouldEqual` approvalAmount
      --   -- minting process
      --   let geohash = mkBytesN s32 "420"
      --       radius = mkUIntN s256 10
      --       stake = mkUIntN s256 1
      --       owner = account1
      --       mintAction = SignalToken.mintSignal (txOpts # _to ?~ signalToken)
      --                                           { owner, stake, geohash, radius }
      --   -- SignalToken.Transfer
      --   -- @TODO: figure out how to get both the transfer and `TrackedToken` event
      --   Tuple _ (SignalToken.Transfer trx) <- assertWeb3 provider $
      --     takeEvent (Proxy :: Proxy SignalToken.Transfer) signalToken mintAction
      --   -- verify ownership/transfer
      --   trx._to `shouldEqual` owner
      --   -- a newly minted signal is always from the `zeroAddr`
      --   trx._from `shouldEqual` zeroAddr
      -- -- @NOTE: at this point all contracts are already deployed
      -- -- to test for a successfully deployed contract, verify that
      -- -- all global get functions are pointed to the correct contract addresses
      -- it "can verify the signal market is deployed" do
      --   let txOpts = defaultTransactionOptions # _to ?~ signalMarket
      --   -- global constructor calls
      --   foamTokenAddr <- assertStorageCall provider $
      --                    SignalMarket.foamToken txOpts Latest
      --   signalTokenAddr <- assertStorageCall provider $
      --                      SignalMarket.signalToken txOpts Latest
      --   foamTokenAddr `shouldEqual` foamToken
      --   signalTokenAddr `shouldEqual` signalTokenAddr

      it "can list signal tokens for sale" do
        -- @NOTE: approve a signal token for transfer to SignalMarket contract
        -- SignalToken.approve :: TransactionOptions NoPay -> { _to :: Address, _tokenId :: (UIntN (D2 :& D5 :& DOne D6)) } -> Web3 HexString

        -- SignalMarket.forSale :: TransactionOptions NoPay -> { _tokenId :: (UIntN (D2 :& D5 :& DOne D6)), _price :: (UIntN (D2 :& D5 :& DOne D6)) } -> Web3 HexString
        -- newtype SignalForSale = SignalForSale {signalId :: (UIntN (D2 :& D5 :& DOne D6)),price :: (UIntN (D2 :& D5 :& DOne D6)),saleId :: (UIntN (D2 :& D5 :& DOne D6))}

        -- signalToSale :: TransactionOptions NoPay -> ChainCursor -> (UIntN (D2 :& D5 :& DOne D6)) -> Web3 (Either CallError (UIntN (D2 :& D5 :& DOne D6)))

        let approvalAmount = mkUIntN s256 100
            approveAction =
              FoamToken.approve (txOpts1 # _to ?~ foamToken)
                                { _spender: signalToken
                                , _value: approvalAmount
                                }
            geohash = mkBytesN s32 "420"
            radius = mkUIntN s256 10
            stake = mkUIntN s256 1
            owner = account1
            mintAction =
              SignalToken.mintSignal (txOpts1 # _to ?~ signalToken) { owner
                                                                    , stake
                                                                    , geohash
                                                                    , radius
                                                                    }
            signalApproveAction _tokenId =
              SignalToken.approve (txOpts1 # _to ?~ signalToken) { _to: signalMarket
                                                                 , _tokenId
                                                                 }
            forSaleAction _tokenId =
              SignalMarket.forSale (txOpts1 # _to ?~ signalMarket) { _tokenId
                                                                   , _price: mkUIntN s256 200
                                                                   }

        -- approve some foam
        Tuple _ approval <- assertWeb3 provider $
          takeEvent (Proxy :: Proxy FoamToken.Approval) foamToken approveAction
        log $ "Approved Foam: " <> show approval

        -- then mint a new signal token
        Tuple _ tt@(SignalToken.TrackedToken token) <- assertWeb3 provider $
          takeEvent (Proxy :: Proxy SignalToken.TrackedToken) signalToken mintAction
        log $ "Signal Minted: " <> show tt

        -- approve minted signal for signal market
        Tuple _ signalApproval <- assertWeb3 provider $
          takeEvent (Proxy :: Proxy SignalToken.Approval) signalToken $ signalApproveAction token.tokenID
        log $ "Signal Token Approved: " <> show signalApproval

        -- -- mark signal as for sale
        Tuple _ sale <- assertWeb3 provider $
           takeEvent (Proxy :: Proxy SignalMarket.SignalForSale) signalMarket (forSaleAction token.tokenID)
        -- check hash
        log $ "Signal for Sale: " <> show sale
        pure unit

      pending' "can buy signal tokens" do
        pure unit
