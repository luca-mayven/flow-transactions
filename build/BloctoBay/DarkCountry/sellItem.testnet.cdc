import FungibleToken from 0x9a0766d93b6608b7
import NonFungibleToken from 0x631e88ae7f1d7c20
import NFTStorefront from 0x94b06cfca1d8a476
import Marketplace from 0xe1aa310cfe7750c4
import FlowToken from 0x7e60df042a9c0868
import DarkCountry from 0xe2759c7e9a894ff1

transaction(saleItemID: UInt64, saleItemPrice: UFix64) {
    let flowTokenReceiver: Capability<&FlowToken.Vault{FungibleToken.Receiver}>
    let darkCountryProvider: Capability<&DarkCountry.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>
    let storefront: &NFTStorefront.Storefront
    let storefrontPublic: Capability<&NFTStorefront.Storefront{NFTStorefront.StorefrontPublic}>

    prepare(signer: AuthAccount) {
        // Create Storefront if it doesn't exist
        if signer.borrow<&NFTStorefront.Storefront>(from: NFTStorefront.StorefrontStoragePath) == nil {
            let storefront <- NFTStorefront.createStorefront() as! @NFTStorefront.Storefront
            signer.save(<-storefront, to: NFTStorefront.StorefrontStoragePath)
            signer.link<&NFTStorefront.Storefront{NFTStorefront.StorefrontPublic}>(
                NFTStorefront.StorefrontPublicPath,
                target: NFTStorefront.StorefrontStoragePath)
        }

        // We need a provider capability, but one is not provided by default so we create one if needed.
        let darkCountryCollectionProviderPrivatePath = /private/darkCountryCollectionProviderForNFTStorefront
        if !signer.getCapability<&DarkCountry.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>(darkCountryCollectionProviderPrivatePath)!.check() {
            signer.link<&DarkCountry.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>(darkCountryCollectionProviderPrivatePath, target: DarkCountry.CollectionStoragePath)
        }

        self.flowTokenReceiver = signer.getCapability<&FlowToken.Vault{FungibleToken.Receiver}>(/public/flowTokenReceiver)!
        assert(self.flowTokenReceiver.borrow() != nil, message: "Missing or mis-typed FlowToken receiver")

        self.darkCountryProvider = signer.getCapability<&DarkCountry.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic}>(darkCountryCollectionProviderPrivatePath)!
        assert(self.darkCountryProvider.borrow() != nil, message: "Missing or mis-typed DarkCountry.Collection provider")

        self.storefront = signer.borrow<&NFTStorefront.Storefront>(from: NFTStorefront.StorefrontStoragePath)
            ?? panic("Missing or mis-typed NFTStorefront Storefront")

        self.storefrontPublic = signer.getCapability<&NFTStorefront.Storefront{NFTStorefront.StorefrontPublic}>(NFTStorefront.StorefrontPublicPath)
        assert(self.storefrontPublic.borrow() != nil, message: "Could not borrow public storefront from address")
    }

    execute {
        // Remove old listing
        if let listingID = Marketplace.getListingID(nftType: Type<@DarkCountry.NFT>(), nftID: saleItemID) {
            let listingIDs = self.storefront.getListingIDs()
            if listingIDs.contains(listingID) {
                self.storefront.removeListing(listingResourceID: listingID)
            }
            Marketplace.removeListing(id: listingID)
        }

        // Create SaleCuts
        var saleCuts: [NFTStorefront.SaleCut] = []
        let requirements = Marketplace.getSaleCutRequirements(nftType: Type<@DarkCountry.NFT>())
        var remainingPrice = saleItemPrice
        for requirement in requirements {
            let price = saleItemPrice * requirement.ratio
            saleCuts.append(NFTStorefront.SaleCut(
                receiver: requirement.receiver,
                amount: price
            ))
            remainingPrice = remainingPrice - price
        }
        saleCuts.append(NFTStorefront.SaleCut(
            receiver: self.flowTokenReceiver,
            amount: remainingPrice
        ))

        // Add listing
        let id = self.storefront.createListing(
            nftProviderCapability: self.darkCountryProvider,
            nftType: Type<@DarkCountry.NFT>(),
            nftID: saleItemID,
            salePaymentVaultType: Type<@FlowToken.Vault>(),
            saleCuts: saleCuts
        )
        Marketplace.addListing(id: id, storefrontPublicCapability: self.storefrontPublic)
    }
}