import React from 'react';
import Layout from '../components/Layout';
import QrCodeGenerator from '../components/QrCodeGenerator';
import QrCodeAsyncGenerator from '../components/QrCodeAsyncGenerator';
import QrCodeList from '../components/QrCodeList';

const QrCodePage: React.FC = () => {
  return (
    <Layout>
      <QrCodeGenerator />
      <QrCodeAsyncGenerator />
      <QrCodeList />
    </Layout>
  );
};

export default QrCodePage;
