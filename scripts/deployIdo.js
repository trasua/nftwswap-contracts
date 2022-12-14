const { ethers, network } = require('hardhat')
const fs = require('fs')

const DAY = 60 * 60 * 24 * 1000

const deploy = async () => {
    let fo = JSON.parse(fs.readFileSync(`${network.name}_address.json`))

    const [signer, IDO] = await Promise.all([
        ethers.getSigner(),
        ethers.getContractFactory('IDO'),
    ])
    const ido = await IDO.deploy(
        fo.tokenAddress,
        fo.usdtAddress,
        '0x0B2c704a2F23E56E41a7acA9FDC9e5e5A52240Cf',
        1665648000, // start buy time
        1665820800, // end buy time
        1665648000, // claim time
        1665993600 // cliff time
    )
    await ido.deployed()

    fo.idoAddress = ido.address
    fs.writeFileSync(
        `${network.name}_address.json`,
        JSON.stringify(fo, null, 4)
    )

    console.log('Contract deploy to a address:', ido.address)
}

deploy()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error)
        process.exit(1)
    })
