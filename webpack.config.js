const path = require("path");
const webpack = require("webpack");
const HtmlWebpackPlugin = require("html-webpack-plugin");
const TerserPlugin = require("terser-webpack-plugin");
const CopyPlugin = require("copy-webpack-plugin");
const fs = require('fs'); // Ensure fs is imported

const network =
    process.env.DFX_NETWORK ||
    (process.env.NODE_ENV === "production" ? "ic" : "local");

function initCanisterEnv() {
    let localCanisters, prodCanisters;
    try {
        localCanisters = require(path.resolve(
            ".dfx",
            "local",
            "canister_ids.json"
        ));
    } catch (error) {
        console.log("No local canister_ids.json found. Continuing production");
    }
    try {
        prodCanisters = require(path.resolve("canister_ids.json"));
    } catch (error) {
        console.log("No production canister_ids.json found. Continuing with local");
    }

    const canisterConfig = network === "local" ? localCanisters : prodCanisters;

    return Object.entries(canisterConfig).reduce((prev, current) => {
        const [canisterName, canisterDetails] = current;
        prev[canisterName.toUpperCase() + "_CANISTER_ID"] =
            canisterDetails[network];
        return prev;
    }, {});
}

const canisterEnvVariables = initCanisterEnv();

const isDevelopment = process.env.NODE_ENV !== "production";

const internetIdentityUrl = network === "local"
    ? `http://${canisterEnvVariables["INTERNET_IDENTITY_CANISTER_ID"]}.localhost:4943/`
    : `https://identity.ic0.app`

const frontendDirectory = "frontend";

// Define the entry points, excluding auth.js
const frontendEntry = path.join("src", frontendDirectory, "src");

module.exports = {
    target: "web",
    mode: isDevelopment ? "development" : "production",
    entry: {
        // Include all JS files in the frontend directory except auth.js
        ...Object.fromEntries(
            fs.readdirSync(frontendEntry)
                .filter(file => file.endsWith('.js')) // Include all .js files
                .map(file => [file.replace('.js', ''), path.resolve(frontendEntry, file)]) // Use path.resolve for absolute paths
        )
    },
    devtool: isDevelopment ? "source-map" : false,
    optimization: {
        minimize: !isDevelopment,
        minimizer: [new TerserPlugin()],
    },
    resolve: {
        extensions: [".js", ".jsx"], // Added .jsx to the list
        fallback: {
            assert: require.resolve("assert/"),
            buffer: require.resolve("buffer/"),
            events: require.resolve("events/"),
            stream: require.resolve("stream-browserify/"),
            util: require.resolve("util/"),
        },
    },
    output: {
        filename: "[name].[contenthash].js", // Use name of the file with a hash for caching
        path: path.join(__dirname, "dist", frontendDirectory),
    },
    module: {
        rules: [
            {
                test: /\.jsx?$/, // Handle .js and .jsx files
                exclude: /node_modules/,
                use: {
                    loader: 'babel-loader', // Ensure Babel is configured to transpile
                    options: {
                        presets: ['@babel/preset-env', '@babel/preset-react'], // Ensure Babel can handle React JSX
                    },
                },
            },
        ],
    },
    plugins: [
        new HtmlWebpackPlugin({
            template: path.join(__dirname, frontendEntry, "auth.html"), // Ensure the correct template
            cache: false,
        }),
        new webpack.EnvironmentPlugin({
            NODE_ENV: "development",
            II_URL: internetIdentityUrl,
            ...canisterEnvVariables,
        }),
        new webpack.ProvidePlugin({
            Buffer: [require.resolve("buffer/"), "Buffer"],
            process: require.resolve("process/browser"),
        }),
        new CopyPlugin({
            patterns: [
                {
                    from: `src/${frontendDirectory}/src/.ic-assets.json*`,
                    to: ".ic-assets.json5",
                    noErrorOnMissing: true
                },
            ],
        }),
    ],
    devServer: {
        proxy: {
            "/api": {
                target: "http://127.0.0.1:4943",
                changeOrigin: true,
                pathRewrite: {
                    "^/api": "/api",
                },
            },
        },
        static: path.resolve(__dirname, "src", frontendDirectory, "assets"),
        hot: true,
        watchFiles: [path.resolve(__dirname, "src", frontendDirectory)],
        liveReload: true,
    },
};
